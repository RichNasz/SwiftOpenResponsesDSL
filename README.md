# SwiftOpenResponsesDSL

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%20%7C%20iOS%2016-lightgrey.svg)](Package.swift)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Built with Grok Build](https://img.shields.io/badge/Built%20with-Grok%20Build-111111)](https://github.com/xai-org/grok-build)

A Swift DSL for the [Open Responses API](https://www.openresponses.org/) -- a multi-provider, interoperable LLM interface specification. Build type-safe LLM requests with result builders, streaming, tool calling, and conversation continuity via `previous_response_id`.

Initially created with Claude Code. Ongoing maintenance uses [Grok Build](https://github.com/xai-org/grok-build) and the latest Grok model available.

## Overview

A domain-specific language (DSL) is a small API shaped for one problem. SwiftOpenResponsesDSL is an embedded DSL: Swift result builders and typed values stand in for the JSON you would otherwise write by hand.

It calls any provider that implements the [Open Responses API](https://www.openresponses.org/), a shared request and response format for text generation, tools, and streaming across model hosts.

Key features:

- **Result builders** -- `@InputBuilder` for input items, `@ResponseConfigBuilder` for configuration, `@SessionBuilder` for mixed items and tools
- **Streaming** -- HTTP server-sent events as semantic `StreamEvent` values, including `output_text.done`, refusals, annotations, reasoning text, and reasoning-summary text
- **Text inference** -- Open Responses 2026-04-24 fields: `top_logprobs`, `safety_identifier`, `prompt_cache_key`, `stream_options`, assistant message `phase`, and output-text logprobs
- **Tool calling** -- Define function tools with `FunctionToolParam`, orchestrate multi-turn tool loops with `ToolSession`
- **Conversation continuity** -- Chain responses with `previous_response_id` instead of re-sending full message history
- **Actor-based client** -- Thread-safe `LLMClient` actor for concurrent usage

A server that exposes a Responses endpoint may not implement the full specification. Optional Open Responses elements are the ones that vary: assistant `phase`, output-text `logprobs`, and the other request configuration fields. A server may omit them. This package sends and decodes the optional HTTP fields it implements, and it accepts a response that omits them. The list is [Optional spec elements](Spec/SwiftOpenResponsesDSL.md#optional-spec-elements). The client contract is in [`Spec/SwiftOpenResponsesDSL.md`](Spec/SwiftOpenResponsesDSL.md). `swift test` runs the live suite against LM Studio at `http://127.0.0.1:1234` with model `openai/gpt-oss-20b`. That server accepts the calls and returns a decoded response, and it skips some of those optional fields: it can omit `safety_identifier` and `prompt_cache_key`, rewrite `frequency_penalty` and `service_tier`, reject `item_reference` and object `tool_choice` with HTTP 400, ignore JSON `text.format`, return empty `logprobs`, and put reasoning on the completed response without reasoning deltas. The test rules are in [`Spec/LiveTesting.md`](Spec/LiveTesting.md).

Streaming in this package is HTTP server-sent events. The package does not cover every Open Responses surface. WebSocket transport, context compaction (`POST /v1/responses/compact`), video input, reasoning-item round-trip, and non-string tool output are not implemented. Unknown output item types fail decoding. They are not ignored. The inventory is [`Spec/Unimplemented.md`](Spec/Unimplemented.md).

## Quick Start

### Installation

Add SwiftOpenResponsesDSL to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RichNasz/SwiftOpenResponsesDSL.git", from: "0.2.0")
]
```

Then add it as a dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["SwiftOpenResponsesDSL"]
)
```

### Minimal Example

```swift
import SwiftOpenResponsesDSL

let client = try LLMClient(
    baseURL: "https://api.openai.com/v1/responses",
    apiKey: "your-api-key"
)
await client.prewarm()

let request = try ResponseRequest(model: "gpt-4o", text: "Hello, world!")
let response = try await client.send(request)
print(response.firstOutputText ?? "No response")
```

`prewarm` sends `GET` on this client's session and returns after the request starts. Open Responses has no prewarm operation.

## Usage Examples

### Basic Non-Streaming

Call `await client.prewarm()` once after creating the client. It sends `GET` on that client's session and returns after the request starts. Open Responses has no prewarm operation.

Use the text initializer for simple prompts, or the `@InputBuilder` for structured conversations:

```swift
// Simple text input
let request = try ResponseRequest(model: "gpt-4o", text: "Explain Swift concurrency")
let response = try await client.send(request)
print(response.firstOutputText ?? "")

// Structured input with result builder
let request = try ResponseRequest(model: "gpt-4o") {
    System("You are a helpful assistant.")
    User("What is the Open Responses API?")
}
let response = try await client.send(request)
print(response.firstOutputText ?? "")
```

### Basic Streaming

Enable streaming by setting `stream: true` and using `client.stream()`:

```swift
let request = try ResponseRequest(model: "gpt-4o", stream: true, text: "Write a haiku about Swift")

for try await event in client.stream(request) {
    switch event {
    case .contentPartDelta(let delta, _, _):
        print(delta, terminator: "")
    case .responseCompleted:
        print() // newline
    default:
        break
    }
}
```

### Conversation Continuity

Use `PreviousResponseId` to chain responses without re-sending the full conversation history:

```swift
let first = try ResponseRequest(model: "gpt-4o", text: "My name is Alice.")
let firstResponse = try await client.send(first)

let followUp = try ResponseRequest(model: "gpt-4o", config: {
    try PreviousResponseId(firstResponse.id)
}, text: "What is my name?")
let followUpResponse = try await client.send(followUp)
print(followUpResponse.firstOutputText ?? "")
```

### File Input

`UserFile` sends an `input_file` part. Nil fields are omitted.

```swift
let request = try ResponseRequest(model: "gpt-4o") {
    UserFile(filename: "notes.txt", fileData: "aGVsbG8=", fileURL: "https://example.com/notes.txt")
    User("Summarize this file.")
}
let response = try await client.send(request)
print(response.firstOutputText ?? "")
```

### Text Inference

Set the Open Responses 2026-04-24 fields you need. Resend `phase` when a later turn includes prior assistant text. A server may omit these optional fields.

```swift
let request = try ResponseRequest(model: "gpt-4o", stream: true, config: {
    try TopLogprobs(5)
    try SafetyIdentifier("user-42")
    try PromptCacheKey("cache-abc")
    StreamOptions(includeObfuscation: false)
}) {
    Assistant("Draft answer", phase: .commentary, id: "msg_1")
    User("Revise the draft.")
}
for try await event in client.stream(request) {
    if case .contentPartDelta(let delta, _, _) = event {
        print(delta, terminator: "")
    }
}
```

### Tool Calling

Define function tools with `FunctionToolParam` and use `ToolSession` to orchestrate the tool-calling loop:

```swift
let weatherTool = FunctionToolParam(
    name: "get_weather",
    description: "Get current weather for a city",
    parameters: .object(
        properties: [
            "city": .string(description: "City name")
        ],
        required: ["city"]
    )
)

let session = ToolSession(
    client: client,
    tools: [weatherTool],
    handlers: [
        "get_weather": { arguments in
            return "{\"temperature\": \"72F\", \"condition\": \"sunny\"}"
        }
    ]
)

let result = try await session.run(
    model: "gpt-4o",
    input: [User("What's the weather in San Francisco?")]
)
print(result.response.firstOutputText ?? "")
```

### Macro-Powered Tools

Use `SwiftLLMToolMacros` to define tools with zero boilerplate. The `@LLMTool` macro synthesizes JSON schema and decoding automatically:

```swift
import SwiftOpenResponsesDSL
import SwiftLLMToolMacros

/// Get the current weather for a location.
@LLMTool
struct GetCurrentWeather {
    @LLMToolArguments
    struct Arguments {
        @LLMToolGuide(description: "City and state, e.g. Alpharetta, GA")
        var location: String
        @LLMToolGuide(description: "Temperature unit", .anyOf(["celsius", "fahrenheit"]))
        var unit: String = "celsius"
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let temp = arguments.unit == "celsius" ? "22°C" : "72°F"
        return ToolOutput(content: "{\"temperature\": \"\(temp)\"}")
    }
}

let agent = try Agent(client: client, model: "gpt-4o") {
    System("You are a weather assistant.")
    AgentTool(GetCurrentWeather())
}

let reply = try await agent.run("What's the weather in Paris?")
print(reply)
```

## Requirements

- Swift 6.2+
- macOS 13.0+ / iOS 16.0+
- Depends on [SwiftLLMToolMacros](https://github.com/RichNasz/SwiftLLMToolMacros) 0.2.0+ for JSON Schema types and `@LLMTool` macro support

## Agent Skill

This project includes [Agent Skills](https://agentskills.io) for AI coding assistants. Skills are optional — the package works the same without them. Skills are only useful if you use an agent that implements the [agentskills.io](https://agentskills.io) specification (Grok Build, Claude Code, Cursor, Gemini CLI, etc.).

| Skill | Role | Path |
|---|---|---|
| `using-swift-open-responses-dsl` | Reference: API surface, config params, tool calling, streaming, reasoning, errors | [`skills/using-swift-open-responses-dsl/SKILL.md`](skills/using-swift-open-responses-dsl/SKILL.md) |
| `design-responses-app` | Process: step-by-step workflow for designing an app from requirements | [`skills/design-responses-app/SKILL.md`](skills/design-responses-app/SKILL.md) |

The macro skills from [SwiftLLMToolMacros](https://github.com/RichNasz/SwiftLLMToolMacros) are also relevant when defining tools:

| Skill | Role |
|---|---|
| `using-swift-llm-tool-macros` | Reference: macro API, type mapping, constraints, pitfalls |
| `design-llm-tool` | Process: step-by-step workflow for designing a tool from a description |

### Installing the Skills

Adding SwiftOpenResponsesDSL as an SPM dependency does **not** make the skills available to your agent — SPM downloads sources into `.build/checkouts/`, which agents don't scan. You need to copy the skill folders into your project so your agent can discover them.

**Step 1:** Resolve packages (if not already done):

```bash
swift package resolve
```

**Step 2:** Copy all four skills into the directory your agent scans.

Claude Code and other agents that scan a repo-root `skills/` directory:

```bash
mkdir -p skills

# DSL skills (from this package)
cp -r .build/checkouts/SwiftOpenResponsesDSL/skills/using-swift-open-responses-dsl \
      skills/using-swift-open-responses-dsl
cp -r .build/checkouts/SwiftOpenResponsesDSL/skills/design-responses-app \
      skills/design-responses-app

# Macro skills (from the SwiftLLMToolMacros dependency)
cp -r .build/checkouts/SwiftLLMToolMacros/skills/using-swift-llm-tool-macros \
      skills/using-swift-llm-tool-macros
cp -r .build/checkouts/SwiftLLMToolMacros/skills/design-llm-tool \
      skills/design-llm-tool
```

Grok Build scans `.grok/skills/`, not `skills/`:

```bash
mkdir -p .grok/skills

cp -r .build/checkouts/SwiftOpenResponsesDSL/skills/using-swift-open-responses-dsl \
      .grok/skills/using-swift-open-responses-dsl
cp -r .build/checkouts/SwiftOpenResponsesDSL/skills/design-responses-app \
      .grok/skills/design-responses-app

cp -r .build/checkouts/SwiftLLMToolMacros/skills/using-swift-llm-tool-macros \
      .grok/skills/using-swift-llm-tool-macros
cp -r .build/checkouts/SwiftLLMToolMacros/skills/design-llm-tool \
      .grok/skills/design-llm-tool
```

This installs all four complementary skills:

| Skill | Package | Role |
|---|---|---|
| `using-swift-open-responses-dsl` | SwiftOpenResponsesDSL | Reference: DSL API surface |
| `design-responses-app` | SwiftOpenResponsesDSL | Process: designing an app |
| `using-swift-llm-tool-macros` | SwiftLLMToolMacros | Reference: macro API surface |
| `design-llm-tool` | SwiftLLMToolMacros | Process: designing a tool struct |

Install all four for the best experience, or pick only the ones relevant to your workflow.

### Using Skills with Grok Build

[Grok Build](https://x.ai) discovers project skills from `.grok/skills/<name>/SKILL.md`. After copying the skill folders there, Grok loads a skill when the task matches its description.

Invoke a skill directly:

```
/using-swift-open-responses-dsl
/design-responses-app
```

To verify, run `grok inspect` and confirm both skills are listed.

**Tip:** If the skills live outside `.grok/skills/`, add that directory under `[skills] paths` in `~/.grok/config.toml`, or point at it from the project's `AGENTS.md`:

```markdown
## Skills
See `path/to/skills/` for Agent Skills that provide SwiftOpenResponsesDSL and SwiftLLMToolMacros API knowledge.
```

### Using Skills with Claude Code

[Claude Code](https://claude.ai/code) automatically discovers skills from a `skills/` directory at your project root. After copying the skill folders (see above), Claude Code will load them when they match your task context.

You can also invoke a skill directly during a conversation:

```
/skill using-swift-open-responses-dsl
/skill design-responses-app
```

To verify skills are available, ask Claude Code: *"What skills do you have for SwiftOpenResponsesDSL?"*

**Tip:** If you are working in a monorepo or the skills are installed in a non-standard location, you can reference them from your project's `CLAUDE.md`:

```markdown
## Skills
See `path/to/skills/` for Agent Skills that provide SwiftOpenResponsesDSL and SwiftLLMToolMacros API knowledge.
```

### Spec-Driven Development

If you use an AI coding agent, consider writing WHAT and HOW specs before generating code. See [docs/SpecDrivenDevelopment.md](docs/SpecDrivenDevelopment.md) for the workflow guide and [Examples/Specs/](Examples/Specs/) for sample specs.

## License

SwiftOpenResponsesDSL is available under the Apache License 2.0. See [LICENSE](LICENSE) for details.
