---
name: design-responses-app
description: >
  Step-by-step process for designing and implementing a Swift application that uses
  SwiftOpenResponsesDSL for the Open Responses API. Use this when translating requirements
  into a working LLM integration with tool calling, streaming, or multi-turn conversations.
  Complements the using-swift-open-responses-dsl reference skill. Scoped to DSL wiring
  only -- does not cover @LLMTool struct design.
---

# Designing an Open Responses API Application

Use this process when asked to build an LLM-powered feature using SwiftOpenResponsesDSL. Work through the steps in order. Each step produces a decision; collect all decisions before writing the final code.

## Step 1: Choose the Interaction Pattern

Ask: how does the user interact with the LLM?

| Pattern | Use When | Type |
|---|---|---|
| **One-shot** (`client.send`) | Single request/response, no tools, no follow-ups | `ResponseRequest` + `LLMClient` |
| **ToolSession** | Single conversation with tool calling, no persistent state | `ToolSession` |
| **Agent** | Multi-turn conversations across user messages, persistent state | `Agent` actor |

**Decision rules:**
- If the LLM needs to call functions → use **ToolSession** or **Agent**
- If the user sends multiple messages across time (chat interface) → use **Agent**
- If it is a single request with tools that resolves in one exchange → use **ToolSession**
- If it is a simple prompt with no tools and no follow-up → use **one-shot**

**Key difference:** ToolSession accumulates full conversation history in the input array across tool-calling iterations. Agent uses `previous_response_id` for conversation continuity across separate user turns.

## Step 2: Select and Configure the Model

Choose a model string and any model-specific configuration.

```swift
// Standard model
let model = "gpt-4o"

// Reasoning model — requires Reasoning config
let model = "o3-mini"
```

**If using a reasoning model**, add `Reasoning(effort:summary:)`:

| Effort | Use When |
|---|---|
| `.low` | Simple questions, cost-sensitive |
| `.medium` | Balanced reasoning |
| `.high` | Complex multi-step problems |
| `.xhigh` | Maximum reasoning depth |

Summary is optional: `.concise` for brief summaries, `.detailed` for full traces, `.auto` to let the model decide.

## Step 3: Define Tools (If Needed)

Skip this step if no tools are needed.

**Prefer macro-powered tools** (`@LLMTool` from SwiftLLMToolMacros) over manual `FunctionToolParam` construction. Macros generate JSON Schema at compile time and pair definition with implementation.

```swift
/// Get the current weather for a location.
@LLMTool
struct GetWeather {
    @LLMToolArguments
    struct Arguments {
        @LLMToolGuide(description: "City name")
        var location: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        ToolOutput(content: "{\"temperature\": \"72F\"}")
    }
}
```

Bridge to DSL with `AgentTool`:

```swift
AgentTool(GetWeather())           // default
AgentTool(GetWeather(), strict: true)  // strict JSON Schema validation
```

**Use manual `FunctionToolParam`** only when:
- The tool schema is dynamic (built at runtime)
- You cannot add SwiftLLMToolMacros as a dependency
- You need a tool with no implementation (forwarding to external system)

For detailed tool design guidance, consult the `design-llm-tool` skill.

## Step 4: Compose Configuration

Decide which `ResponseConfigParameter` values to set. Only set parameters you need — all default to `nil`.

**Common configurations:**

```swift
// Creative text generation
try Temperature(1.2)
try MaxOutputTokens(4000)

// Precise, structured output
try Temperature(0.0)
TextConfig(TextParam(format: .jsonObject))

// Reasoning model
Reasoning(effort: .high, summary: .concise)

// Tool calling with forced tool use
ToolChoiceParam(.required)

// Long-running requests
try RequestTimeout(300)
try ResourceTimeout(600)
```

**ToolChoice decision rules:**
- `.auto` (default) — model decides whether to call tools
- `.required` — force the model to call at least one tool
- `.function("name")` — force a specific tool (useful for routing)
- `.none` — disable tools for this request even if tools are registered

## Step 5: Choose Streaming vs Non-Streaming

| Approach | Use When |
|---|---|
| **Non-streaming** (`send` / `run`) | Background processing, batch jobs, simple scripts |
| **Streaming** (`stream`) | Real-time UI, chat interfaces, progress indicators |

**Non-streaming** returns a complete `ResponseObject` or `String`:

```swift
// One-shot
let response = try await client.send(request)

// ToolSession
let result = try await session.run("prompt")

// Agent
let reply = try await agent.run("prompt")
```

**Streaming** returns `AsyncThrowingStream` of events:

```swift
// Agent streaming
for try await event in await agent.stream("prompt") {
    switch event {
    case .llm(.contentPartDelta(let delta, _, _)):
        print(delta, terminator: "")  // real-time text
    case .toolCallStarted(_, let name, _):
        print("[calling \(name)]")
    case .toolCallCompleted(_, let name, let output, let duration):
        print("[done: \(name)]")
    case .usageUpdate(let usage, let iteration):
        print("[tokens: \(usage.totalTokens)]")
    default:
        break
    }
}
```

## Step 6: Structure Error Handling

Decide which errors to handle explicitly:

| Error | When It Occurs | Recommended Action |
|---|---|---|
| `LLMError.rateLimit` | HTTP 429 | Exponential backoff and retry |
| `LLMError.serverError(code, message)` | Non-2xx HTTP | Log and surface to user |
| `LLMError.networkError(description)` | Connection failure | Retry with timeout |
| `LLMError.maxIterationsExceeded(max)` | Tool loop ran too long | Increase `maxIterations` or simplify prompt |
| `LLMError.unknownTool(name)` | Model called unregistered tool | Check tool registration |
| `LLMError.toolExecutionFailed(name, msg)` | Tool handler threw | Fix tool implementation |
| `LLMError.missingModel` | Empty model string | Check configuration |
| `LLMError.decodingFailed(description)` | Response parsing failed | Check API compatibility |

**Minimum error handling** for production:

```swift
do {
    let reply = try await agent.run("Hello")
} catch LLMError.rateLimit {
    // retry after delay
} catch LLMError.serverError(let code, let message) {
    log("Server error \(code): \(message ?? "")")
} catch {
    log("Unexpected: \(error)")
}
```

## Step 7: Assemble the Final Code

With all decisions made, write the code in this order:

1. Tool structs (`@LLMTool` / `@LLMToolArguments`)
2. Client initialization (`LLMClient`)
3. Session or Agent setup (declarative `@SessionBuilder` preferred)
4. Request execution (send/run/stream)
5. Error handling wrapper

**Pre-flight checklist:**
- [ ] `import SwiftOpenResponsesDSL` is present
- [ ] `import SwiftLLMToolMacros` is present (if using macros)
- [ ] Client `baseURL` ends with `/v1/responses` (not `/v1/chat/completions`)
- [ ] Agent uses `instructions:` not `systemPrompt:` (explicit init)
- [ ] ToolSession uses `input:` not `messages:`
- [ ] All `await` calls are in an async context
- [ ] Config params that validate use `try` (Temperature, TopP, MaxOutputTokens, etc.)
- [ ] Tools are registered with handlers (ToolSession) or as AgentTools (Agent/SessionBuilder)

## Complete Example

```swift
import SwiftOpenResponsesDSL
import SwiftLLMToolMacros

/// Get the current weather for a location.
@LLMTool
struct GetWeather {
    @LLMToolArguments
    struct Arguments {
        @LLMToolGuide(description: "City name")
        var location: String
        @LLMToolGuide(description: "Unit", .anyOf(["celsius", "fahrenheit"]))
        var unit: String?
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let temp = arguments.unit == "fahrenheit" ? "72F" : "22C"
        return ToolOutput(content: "{\"temperature\": \"\(temp)\", \"location\": \"\(arguments.location)\"}")
    }
}

let client = try LLMClient(
    baseURL: "https://api.openai.com/v1/responses",
    apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
)

let agent = try Agent(client: client, model: "gpt-4o") {
    System("You are a helpful weather assistant. Always use the get_weather tool.")
    AgentTool(GetWeather())
}

// Streaming interaction
for try await event in await agent.stream("What's the weather in Paris and London?") {
    switch event {
    case .llm(.contentPartDelta(let delta, _, _)):
        print(delta, terminator: "")
    case .toolCallCompleted(_, let name, let output, let duration):
        print("\n[\(name) completed in \(duration): \(output)]")
    default:
        break
    }
}
print()  // final newline

// Multi-turn continuity (uses previous_response_id automatically)
let followUp = try await agent.run("Which city is warmer?")
print(followUp)
```

## Boundary

This skill covers SwiftOpenResponsesDSL application design only. For designing `@LLMTool` structs (arguments, types, constraints), consult the `design-llm-tool` skill. For macro API reference, consult the `using-swift-llm-tool-macros` skill.
