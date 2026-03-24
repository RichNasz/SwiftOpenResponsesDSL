# SwiftOpenResponsesDSL

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%20%7C%20iOS%2016-lightgrey.svg)](Package.swift)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-blueviolet?logo=claude)](https://claude.ai/code)

A Swift DSL for the [Open Responses API](https://www.openresponses.org/) -- a multi-provider, interoperable LLM interface specification. Build type-safe LLM requests with result builders, streaming, tool calling, and conversation continuity via `previous_response_id`.

## Overview

SwiftOpenResponsesDSL provides an embedded domain-specific language for interacting with any LLM provider that implements the [Open Responses API](https://www.openresponses.org/) specification. Instead of manually constructing JSON payloads, you use Swift result builders to compose requests declaratively.

Key features:

- **Result builders** -- `@InputBuilder` for input items, `@ResponseConfigBuilder` for configuration, `@SessionBuilder` for mixed items and tools
- **Streaming** -- Async sequence of semantic `StreamEvent` values (deltas, completions, errors)
- **Tool calling** -- Define function tools with `FunctionToolParam`, orchestrate multi-turn tool loops with `ToolSession`
- **Conversation continuity** -- Chain responses with `previous_response_id` instead of re-sending full message history
- **Actor-based client** -- Thread-safe `LLMClient` actor for concurrent usage

## Quick Start

### Installation

Add SwiftOpenResponsesDSL to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RichNasz/SwiftOpenResponsesDSL.git", from: "0.1.0")
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

let request = try ResponseRequest(model: "gpt-4o", text: "Hello, world!")
let response = try await client.send(request)
print(response.firstOutputText ?? "No response")
```

## Usage Examples

### Basic Non-Streaming

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
- Depends on [SwiftLLMToolMacros](https://github.com/RichNasz/SwiftLLMToolMacros) 0.1.1+ for JSON Schema types and `@LLMTool` macro support

## Agent Skill

This project includes [Agent Skills](https://agentskills.io) for AI coding assistants. Skills are optional — the package works the same without them. Skills are only useful if you use an agent that implements the [agentskills.io](https://agentskills.io) specification (Claude Code, Cursor, Gemini CLI, etc.).

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

**Step 2:** Copy all four skills into your project's `skills/` directory:

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

This installs all four complementary skills:

| Skill | Package | Role |
|---|---|---|
| `using-swift-open-responses-dsl` | SwiftOpenResponsesDSL | Reference: DSL API surface |
| `design-responses-app` | SwiftOpenResponsesDSL | Process: designing an app |
| `using-swift-llm-tool-macros` | SwiftLLMToolMacros | Reference: macro API surface |
| `design-llm-tool` | SwiftLLMToolMacros | Process: designing a tool struct |

Install all four for the best experience, or pick only the ones relevant to your workflow.

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
