# Weather Assistant — HOW Spec

## Implementation Target

- Package: `SwiftOpenResponsesDSL`
- Macro package: `SwiftLLMToolMacros`
- Imports: `import SwiftOpenResponsesDSL`, `import SwiftLLMToolMacros`

## Interaction Pattern Decision

**Use `Agent`** — the WHAT spec requires multi-turn conversations with persistent context. Agent uses `previous_response_id` for conversation continuity, so follow-up questions like "How about London?" automatically reference prior context.

Do NOT use `ToolSession` — it is for single-conversation tool loops, not persistent multi-turn chat.

## Tool Design

Use `@LLMTool` macro for the `GetWeather` tool:

```swift
/// Get the current weather for a location.
@LLMTool
struct GetWeather {
    @LLMToolArguments
    struct Arguments {
        @LLMToolGuide(description: "City and optional state/country, e.g. Paris, France")
        var location: String

        @LLMToolGuide(description: "Temperature unit preference", .anyOf(["celsius", "fahrenheit"]))
        var unit: String?
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        // Replace with actual weather API call
        let temp = arguments.unit == "fahrenheit" ? "72F" : "22C"
        return ToolOutput(content: """
            {"temperature": "\(temp)", "condition": "sunny", "location": "\(arguments.location)"}
            """)
    }
}
```

**Inline Arguments** — the Arguments type is used by only one tool, so define it nested inside the tool struct.

## Agent Setup

Use the declarative `@SessionBuilder` init:

```swift
let agent = try Agent(client: client, model: "gpt-4o") {
    System("You are a helpful weather assistant. Use the get_weather tool to answer weather questions.")
    AgentTool(GetWeather())
}
```

- `System(...)` in `@SessionBuilder` maps to `instructions` on the Agent
- `AgentTool(GetWeather())` bridges the macro-powered tool with its handler

## Configuration

No additional configuration parameters needed for this use case. The defaults are sufficient:
- Temperature: nil (model default)
- ToolChoice: nil (auto — model decides when to call tools)
- MaxToolIterations: 10 (default)

If the weather API is slow, consider adding `RequestTimeout`:

```swift
let agent = Agent(
    client: client,
    model: "gpt-4o",
    instructions: "You are a helpful weather assistant.",
    tools: [FunctionToolParam(from: GetWeather.toolDefinition)],
    toolHandlers: ["get_weather": { args in /* ... */ }],
    config: [try RequestTimeout(120)]
)
```

## Streaming Implementation

Use `agent.stream()` for real-time output:

```swift
for try await event in await agent.stream(userMessage) {
    switch event {
    case .llm(.contentPartDelta(let delta, _, _)):
        // Append delta to UI text view
        updateUI(delta)
    case .toolCallStarted(_, let name, _):
        showToolIndicator(name: name, status: .started)
    case .toolCallCompleted(_, let name, _, let duration):
        showToolIndicator(name: name, status: .completed(duration))
    case .usageUpdate(let usage, _):
        trackUsage(usage.totalTokens)
    default:
        break
    }
}
```

Key events to handle:
- `.llm(.contentPartDelta)` — real-time text tokens
- `.toolCallStarted` / `.toolCallCompleted` — tool activity for UI
- `.usageUpdate` — token tracking

## Error Handling

```swift
do {
    for try await event in await agent.stream(userMessage) { /* ... */ }
} catch LLMError.rateLimit {
    try await Task.sleep(for: .seconds(retryDelay))
    // retry
} catch LLMError.serverError(let code, let message) {
    showError("Server error \(code)")
} catch LLMError.networkError {
    showError("Network unavailable. Check your connection.")
} catch {
    showError("Something went wrong: \(error.localizedDescription)")
}
```

## Multi-Turn Continuity

No special code needed — `Agent` automatically sets `previous_response_id` on each subsequent call:

```swift
let reply1 = try await agent.run("What's the weather in Paris?")
let reply2 = try await agent.run("How about London?")  // context is preserved
let reply3 = try await agent.run("Which city is warmer?")  // references both
```

To reset the conversation: `await agent.reset()`.

## Expected Output Shape

Given the WHAT spec's acceptance criteria, the implementation should produce:
- A compiled `Agent` actor that handles weather queries
- Streaming output with real-time text and tool activity indicators
- Multi-turn context preservation via `previous_response_id`
- Graceful error handling for network, rate limit, and server errors
