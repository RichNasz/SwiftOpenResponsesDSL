# Tool Support Specification

## Overview

This specification describes the complete tool calling and agent support in SwiftOpenResponsesDSL. The DSL provides Apple FoundationModels-style ergonomics for defining tools, executing tool-calling loops, and building persistent agents — all targeting the Open Responses API.

---

### Convenience Message Types

Shorthand constructors for common message roles:

```swift
System("You are a helpful assistant.")    // InputItem.message(InputMessage(role: .system, ...))
Developer("Follow these rules.")          // InputItem.message(InputMessage(role: .developer, ...))
User("What's the weather?")              // InputItem.message(InputMessage(role: .user, ...))
FunctionOutput(callId: "call_1", output: "{\"temp\": 72}")  // InputItem.functionCallOutput(...)
```

These work anywhere `InputItem` works, including `@InputBuilder` and `@SessionBuilder` blocks.

### Macro-Powered Tools (via SwiftLLMToolMacros)

Using the companion macros package for zero-boilerplate tool definitions:

```swift
@ChatCompletionsTool
struct GetCurrentWeather {
    @ChatCompletionsToolArguments
    struct Arguments {
        @ChatCompletionsToolGuide(description: "City and state, e.g. Alpharetta, GA")
        var location: String
        @ChatCompletionsToolGuide(description: "Unit", .anyOf(["celsius", "fahrenheit"]))
        var unit: String = "celsius"
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        ToolOutput(content: "...")
    }
}
```

Bridged to core DSL types:
- `AgentTool.init<T: ChatCompletionsTool>(_ instance: T)`
- `FunctionToolParam.init(from: ToolDefinition)`

### Manual Tool Definition (JSONSchema)

```swift
let weatherTool = FunctionToolParam(
    name: "get_weather",
    description: "Get current weather for a location",
    parameters: .object(
        properties: [
            "location": .string(description: "City and state"),
            "unit": .string(description: "Unit", enumValues: ["celsius", "fahrenheit"]),
        ],
        required: ["location"]
    )
)
```

### ResponseRequest with Tools

```swift
let request = try ResponseRequest(model: "gpt-4o") {
    try Temperature(0.2)
} input: {
    System("You are a helpful assistant.")
    User("Weather in Alpharetta?")
}
// Tools are set via request.tools = [weatherTool]
```

### FunctionCallItem.decodeArguments() — Typed Argument Decoding

```swift
struct WeatherArgs: Decodable {
    let location: String
    let unit: String
}

let args: WeatherArgs = try functionCallItem.decodeArguments()
```

### ToolSession — Automatic Tool Execution

**Declarative style** (preferred):
```swift
let session = ToolSession(client: client, model: "gpt-4o") {
    System("You are a weather assistant.")
    AgentTool(tool: weatherTool) { args in
        return "{\"temperature\": 72, \"condition\": \"sunny\"}"
    }
}

let result = try await session.run("Weather in Paris?")
print(result.response.firstOutputText ?? "")
```

**Explicit style**:
```swift
let session = ToolSession(
    client: client,
    tools: [weatherTool],
    handlers: ["get_weather": { args in
        return "{\"temperature\": 72, \"condition\": \"sunny\"}"
    }]
)

let result = try await session.run(
    model: "gpt-4o",
    input: [User("Weather in Paris?")]
)
print(result.response.firstOutputText ?? "")
```

Key difference from Chat Completions: The tool loop uses `previous_response_id` instead of re-sending full message history.

### Agent — Persistent Conversations

**Declarative style** (preferred):
```swift
let agent = try Agent(client: client, model: "gpt-4o") {
    System("You are a helpful assistant.")
    AgentTool(tool: weatherTool) { args in
        return "{\"temperature\": 72}"
    }
}

let response1: String = try await agent.run("Weather in Paris?")
let response2: String = try await agent.run("How about London?")
```

Agent uses `lastResponseId` for conversation continuity instead of maintaining full message history.

### Error Handling

```swift
catch LLMError.maxIterationsExceeded(let max) { ... }
catch LLMError.unknownTool(let name) { ... }
catch LLMError.toolExecutionFailed(let name, let message) { ... }
```

For implementation details, see [ToolSupportSpec-HOW.md](ToolSupportSpec-HOW.md).
