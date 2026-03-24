---
name: using-swift-open-responses-dsl
description: >
  Helps the agent use SwiftOpenResponsesDSL to build type-safe LLM request pipelines for the
  Open Responses API with tool calling, sessions, and persistent agents with conversation
  continuity via previous_response_id. Useful when defining ResponseRequest objects, wiring
  LLMTool instances into a ToolSession or Agent, chaining responses across turns, or processing
  streaming events in Swift.
---

# Using SwiftOpenResponsesDSL

## Installation

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RichNasz/SwiftOpenResponsesDSL.git", from: "0.1.0"),
    .package(url: "https://github.com/RichNasz/SwiftLLMToolMacros.git", from: "0.1.0")
]
```

Target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        "SwiftOpenResponsesDSL",
        "SwiftLLMToolMacros"
    ]
)
```

Imports at the top of each file:

```swift
import SwiftOpenResponsesDSL
import SwiftLLMToolMacros  // for @LLMTool, @LLMToolArguments, @LLMToolGuide
```

## LLMClient

```swift
let client = try LLMClient(
    baseURL: "https://api.openai.com/v1/responses",
    apiKey: "your-api-key"
)
```

## Basic Request

```swift
// Simple text
let request = try ResponseRequest(model: "gpt-4o", text: "Explain async/await in Swift")
let response = try await client.send(request)
print(response.firstOutputText ?? "")

// Structured input with @InputBuilder
let request = try ResponseRequest(model: "gpt-4o") {
    System("You are a helpful assistant.")
    User("Explain async/await in Swift.")
}
let response = try await client.send(request)
```

### Convenience Input Functions

| Function | Creates |
|---|---|
| `System("...")` | System message `InputItem` |
| `Developer("...")` | Developer message `InputItem` |
| `User("...")` | User message `InputItem` |
| `UserImage("url", detail: "auto")` | User image `InputItem` |
| `FunctionOutput(callId: "...", output: "...")` | Function call output `InputItem` |

## Configuration Parameters

Use `@ResponseConfigBuilder` to compose parameters:

```swift
let request = try ResponseRequest(model: "gpt-4o", config: {
    try Temperature(0.7)
    try MaxOutputTokens(2000)
    Reasoning(effort: .high, summary: .concise)
}) {
    User("Explain quantum computing.")
}
```

| Parameter | Init | Range/Constraint |
|---|---|---|
| `Temperature` | `try Temperature(0.7)` | 0.0–2.0 |
| `TopP` | `try TopP(0.9)` | 0.0–1.0 |
| `FrequencyPenalty` | `try FrequencyPenalty(0.5)` | -2.0–2.0 |
| `PresencePenalty` | `try PresencePenalty(0.5)` | -2.0–2.0 |
| `MaxOutputTokens` | `try MaxOutputTokens(1000)` | > 0 |
| `Instructions` | `try Instructions("...")` | non-empty |
| `PreviousResponseId` | `try PreviousResponseId("resp_...")` | non-empty |
| `Reasoning` | `Reasoning(effort: .high, summary: .concise)` | see Reasoning section |
| `TruncationParam` | `TruncationParam(.auto)` | `.auto` / `.disabled` |
| `ServiceTierParam` | `ServiceTierParam(.auto)` | `.auto` / `.default` / `.flex` / `.priority` |
| `Metadata` | `Metadata(["key": "val"])` | dictionary |
| `ParallelToolCalls` | `ParallelToolCalls(true)` | Bool |
| `IncludeParam` | `try IncludeParam(["reasoning.encrypted_content"])` | non-empty array |
| `RequestTimeout` | `try RequestTimeout(60)` | 10–900 seconds |
| `ResourceTimeout` | `try ResourceTimeout(300)` | 30–3600 seconds |
| `Store` | `Store(true)` | Bool |
| `Background` | `Background(true)` | Bool |
| `MaxToolCalls` | `try MaxToolCalls(5)` | > 0 |
| `TextConfig` | `TextConfig(TextParam(format: .jsonObject))` | see Structured Output |
| `ToolChoiceParam` | `ToolChoiceParam(.required)` | see ToolChoice |

Parameters with `try` validate their input and throw `LLMError.invalidValue` on failure.

## Conversation Continuity

The Responses API does not require re-sending full message history. Chain responses using `previous_response_id`:

```swift
let first = try ResponseRequest(model: "gpt-4o", text: "My name is Alice.")
let firstResponse = try await client.send(first)

let followUp = try ResponseRequest(model: "gpt-4o", config: {
    try PreviousResponseId(firstResponse.id)
}, text: "What is my name?")
let followUpResponse = try await client.send(followUp)
```

## Reasoning Models

Configure reasoning with `Reasoning(effort:summary:)`:

```swift
let request = try ResponseRequest(model: "o3-mini", config: {
    Reasoning(effort: .high, summary: .concise)
}) {
    User("Solve this step by step: what is 127 * 89?")
}
let response = try await client.send(request)
```

**ReasoningEffort**: `.none`, `.low`, `.medium`, `.high`, `.xhigh`
**ReasoningSummaryType**: `.concise`, `.detailed`, `.auto`

### Accessing Reasoning Output

```swift
response.reasoningItems         // [ReasoningItem] — all reasoning items
response.firstReasoningItem     // ReasoningItem? — first reasoning item
response.reasoningTokens        // Int — reasoning tokens used (0 if unavailable)

// ReasoningItem properties
item.id                         // String
item.summaryText                // String? — concatenated summary entries
item.contentText                // String? — concatenated raw reasoning content
item.encryptedContent           // String? — encrypted reasoning (with IncludeParam)
```

### Reasoning Streaming Events

```swift
case .reasoningSummaryPartAdded(let part, let index, let summaryIndex)
case .reasoningSummaryPartDone(let part, let index, let summaryIndex)
```

## Structured Output

Control the response format with `TextConfig`:

```swift
// JSON object mode
TextConfig(TextParam(format: .jsonObject))

// JSON Schema mode (strict)
TextConfig(TextParam(format: .jsonSchema(
    name: "weather_response",
    schema: .object(properties: ["temp": .string()], required: ["temp"]),
    strict: true
)))

// Verbosity control
TextConfig(TextParam(verbosity: .low))  // .low, .medium, .high
```

## Tool Calling

### Defining Tools

**Macro-powered (recommended):** Use `@LLMTool` from SwiftLLMToolMacros.

```swift
/// Get the current weather for a location.
@LLMTool
struct GetWeather {
    @LLMToolArguments
    struct Arguments {
        @LLMToolGuide(description: "City and state, e.g. San Francisco, CA")
        var location: String

        @LLMToolGuide(description: "Temperature unit", .anyOf(["celsius", "fahrenheit"]))
        var unit: String?
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        ToolOutput(content: "{\"temperature\": \"72F\"}")
    }
}
```

**Manual:** Construct a `FunctionToolParam` directly.

```swift
let weatherTool = FunctionToolParam(
    name: "get_weather",
    description: "Get current weather for a city",
    parameters: .object(
        properties: ["city": .string(description: "City name")],
        required: ["city"]
    )
)
```

**Bridging from a ToolDefinition:**

```swift
let functionTool = FunctionToolParam(from: GetWeather.toolDefinition)
let strictTool = FunctionToolParam(from: GetWeather.toolDefinition, strict: true)
```

**`@ToolsBuilder`** composes `[FunctionToolParam]` arrays declaratively, though `@SessionBuilder` is preferred for most use cases.

### AgentTool — Bridging a Tool to a Session

`AgentTool` pairs a `FunctionToolParam` definition with its handler closure.

```swift
// From an @LLMTool instance (recommended)
AgentTool(GetWeather())

// With strict mode
AgentTool(GetWeather(), strict: true)

// From a manual FunctionToolParam with a handler closure
AgentTool(tool: weatherTool) { argumentsJSON in
    return "{\"temperature\": \"72F\"}"
}
```

The `ToolHandler` type is `@Sendable (String) async throws -> String`.

### ToolChoice

Control how the model selects tools:

```swift
ToolChoiceParam(.auto)                                        // model decides (default)
ToolChoiceParam(.none)                                        // disable tools
ToolChoiceParam(.required)                                    // force tool use
ToolChoiceParam(.function("get_weather"))                     // force specific tool
ToolChoiceParam(.allowedTools(mode: .auto, tools: ["get_weather"]))  // restrict to subset
```

`ToolChoiceMode` for `.allowedTools`: `.none`, `.auto`, `.required`.

## ToolSession

`ToolSession` orchestrates the tool-calling loop, accumulating full conversation history across iterations until the model produces a final response.

### Declarative Init (recommended)

```swift
let session = ToolSession(client: client, model: "gpt-4o") {
    System("You are a weather assistant.")
    AgentTool(GetWeather())
}

let result = try await session.run("What's the weather in Paris?")
print(result.response.firstOutputText ?? "")
```

### Explicit Init

```swift
let session = ToolSession(
    client: client,
    tools: [weatherTool],
    handlers: ["get_weather": { args in "{\"temperature\": \"72F\"}" }]
)

let result = try await session.run(
    model: "gpt-4o",
    input: [User("What's the weather in Paris?")]
)
```

Note: ToolSession uses `input: [InputItem]`, not `messages:`. The two inits differ in their `run` call signature.

### Streaming

```swift
let stream = session.stream("What's the weather in Paris?")
for try await event in stream {
    switch event {
    case .iterationStarted(let n):
        print("[iteration \(n)]")
    case .llm(let streamEvent):
        break  // raw StreamEvent from the model
    case .toolCallStarted(let callId, let name, let arguments):
        print("[calling \(name)]")
    case .toolCallCompleted(let callId, let name, let output, let duration):
        print("[done: \(name) in \(duration)]")
    case .usageUpdate(let usage, let iteration):
        print("[iteration \(iteration): \(usage.totalTokens) tokens]")
    }
}
```

### ToolSessionResult

```swift
result.response           // ResponseObject — final response
result.iterations         // Int — number of tool-calling rounds
result.log                // [ToolCallLogEntry] — tool call log entries
                          //   .name: String, .arguments: String,
                          //   .result: String, .duration: Duration
result.iterationUsages    // [ResponseObject.Usage] — per-iteration token usage
result.totalUsage         // ResponseObject.Usage? — combined usage across iterations
```

## Agent

`Agent` is an actor for persistent multi-turn conversations. It uses `previous_response_id` for continuity — it does not re-send the full history on each turn.

### Declarative Init (recommended)

```swift
let agent = try Agent(client: client, model: "gpt-4o") {
    System("You are a weather assistant.")
    AgentTool(GetWeather())
}

let reply1 = try await agent.run("What's the weather in Paris?")
let reply2 = try await agent.run("How about London?")  // uses previous_response_id
```

### Explicit Init

```swift
let agent = Agent(
    client: client,
    model: "gpt-4o",
    instructions: "You are a weather assistant.",
    tools: [weatherTool],
    toolHandlers: ["get_weather": { args in "{\"temperature\": \"72F\"}" }]
)
```

Note: `Agent` uses `instructions:`, not `systemPrompt:`.

### Agent Methods

All methods require `await` (Agent is an actor):

```swift
try await agent.send("Hello")      // send a turn, returns String
try await agent.run("Hello")       // alias for send
await agent.stream("Hello")        // returns AsyncThrowingStream<ToolSessionEvent, Error>
await agent.reset()                // clear state; next send starts fresh
```

### Agent State

```swift
await agent.lastResponseId   // String? — response ID from the last turn
await agent.lastUsage        // ResponseObject.Usage? — token usage from the last turn
```

### Transcript

```swift
for entry in await agent.transcript {
    switch entry {
    case .userMessage(let msg):               print("[User] \(msg)")
    case .assistantMessage(let msg):          print("[Assistant] \(msg)")
    case .toolCall(let name, let args):       print("[Tool] \(name)(\(args))")
    case .toolResult(let name, _, let dur):   print("[Result] \(name) in \(dur)")
    case .reasoning(let item):               print("[Reasoning] \(item.summaryText ?? "")")
    case .error(let msg):                    print("[Error] \(msg)")
    }
}
```

## Error Handling

```swift
do {
    let reply = try await agent.run("Hello")
} catch LLMError.rateLimit {
    // back off and retry
} catch LLMError.serverError(let code, let message) {
    print("HTTP \(code): \(message ?? "")")
} catch LLMError.networkError(let description) {
    print(description)
} catch LLMError.maxIterationsExceeded(let max) {
    print("Loop exceeded \(max) iterations")
} catch LLMError.unknownTool(let name) {
    print("Model called unregistered tool: \(name)")
} catch LLMError.toolExecutionFailed(let name, let message) {
    print("Tool \(name) failed: \(message)")
}
```

## Common Pitfalls

- **`instructions` not `systemPrompt`** — `Agent` takes `instructions:` in the explicit init, not `systemPrompt:`. `System(...)` in `@SessionBuilder` maps to instructions.
- **`input:` not `messages:`** — `ToolSession.run(model:input:)` takes `input: [InputItem]`, not `messages:`. Use `User("...")` and `System("...")` as `InputItem` values.
- **Continuity model** — `Agent` uses `previous_response_id` for turn continuity. `ToolSession` accumulates full conversation history in the input array (does NOT use `previous_response_id`).
- **`strict` on AgentTool** — `AgentTool(instance, strict: true)` enables strict mode for JSON Schema validation. Default is `nil` (server decides).
- **`agent.stream()` not `agent.streamSend()`** — Streaming on Agent uses `stream`, not `streamSend`. (`streamSend` is SwiftChatCompletionsDSL's name.)
- **`TranscriptEntry.reasoning`** — This DSL's transcript includes `.reasoning(ReasoningItem)` for reasoning model output. SwiftChatCompletionsDSL does not have this case.
- **ToolSessionEvent differences** — Events here (`.iterationStarted`, `.llm`, `.toolCallStarted`, `.toolCallCompleted`, `.usageUpdate`) differ from SwiftChatCompletionsDSL's events.
- **Config params that throw** — `Temperature`, `TopP`, `FrequencyPenalty`, `PresencePenalty`, `MaxOutputTokens`, `Instructions`, `PreviousResponseId`, `IncludeParam`, `RequestTimeout`, `ResourceTimeout`, `MaxToolCalls` all require `try`. Others (`Reasoning`, `TruncationParam`, `Store`, etc.) do not.

## Out of Scope

This skill covers SwiftOpenResponsesDSL wiring only. For designing `@LLMTool` structs, consult the `using-swift-llm-tool-macros` and `design-llm-tool` skills. For the Chat Completions API, consult the `using-swift-chat-completions-dsl` skill.
