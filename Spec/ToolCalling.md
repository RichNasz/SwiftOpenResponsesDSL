# Tool Calling & Agent Capability Specification

## Overview

This specification defines the tool calling and agent orchestration types for SwiftOpenResponsesDSL. These additions enable the DSL to parse function calls from Responses API output, manage the tool-calling loop using `previous_response_id`, and provide a high-level agent abstraction for persistent conversations with tool use.

### FunctionCallItem (output)
Parsed function call from a non-streaming API response output.

- **Fields**: `id: String`, `callId: String`, `name: String`, `arguments: String`, `status: String?`
- **Conformance**: `Sendable`, `Decodable`
- **decodeArguments()**: Generic helper to decode raw JSON arguments into typed Swift values:
  ```swift
  public func decodeArguments<T: Decodable>(_ type: T.Type = T.self) throws -> T
  ```

### FunctionCallOutputItem (input)
Result sent back to the model after executing a function call.

- **Fields**: `callId: String`, `output: String`
- **Conformance**: `Sendable`, `Encodable`
- **JSON**: `type` is always `"function_call_output"`, `call_id` for snake_case

### ToolChoice (enum)
Controls model tool selection behavior.

- **Cases**: `auto`, `none`, `required`, `function(String)`
- **Conformance**: `Sendable`, `Encodable`
- **Encoding**: For the Responses API, `.function(name)` encodes as `{"type":"function","name":"..."}` (no nested function object — different from Chat Completions)

### ToolChoiceParam (struct)
`ResponseConfigParameter` wrapper for `ToolChoice`.

### SessionComponent (enum)
A component that can appear inside a `@SessionBuilder` block.

- **Cases**: `.inputItem(InputItem)`, `.agentTool(AgentTool)`
- **Conformance**: `Sendable`

### SessionBuilder (result builder)
Declarative syntax for configuring sessions with both input items and tools.

- **buildExpression**: Accepts `InputItem` or `AgentTool`
- **Control flow**: `buildEither`, `buildOptional`, `buildArray`

### ToolSession (struct)
Orchestrates the tool-calling loop using `previous_response_id` for conversation continuity.

- **ToolHandler**: `@Sendable (String) async throws -> String`
- **Explicit init**: `client: LLMClient`, `tools: [FunctionToolParam]`, `toolChoice: ToolChoice? = nil`, `maxIterations: Int = 10`, `handlers: [String: ToolHandler]`
- **Declarative init**: `client: LLMClient`, `model: String`, `toolChoice: ToolChoice? = nil`, `maxIterations: Int = 10`, `@SessionBuilder configure: () -> [SessionComponent]`
- **run(model:input:config:)**: Accepts model, input items, config; returns `ToolSessionResult`
- **run(_ prompt:)**: Shorthand for declarative init

Key difference from Chat Completions: The tool loop uses `previous_response_id` instead of re-sending full message history. Each iteration sends only the new function_call_output items plus the previous response ID.

### ToolSessionResult (struct)
- **Fields**: `response: ResponseObject`, `iterations: Int`, `log: [ToolCallLogEntry]`
- **Token usage**: `result.response.usage` surfaces token counts (`inputTokens`, `outputTokens`, `totalTokens`) for the final response in the tool loop. Callers interested in per-iteration totals must sum across intermediate responses manually — `ToolSessionResult` does not accumulate usage across iterations.
- **Agent limitation**: `Agent.run()` and `Agent.send()` return `String` only — usage data is not surfaced. Callers requiring token counts should use `ToolSession` or `client.send()` directly.

### ToolCallLogEntry (struct)
- **Fields**: `name: String`, `arguments: String`, `result: String`, `duration: Duration`

### Agent (actor)
High-level persistent agent with `lastResponseId` for conversation continuity.

- **Explicit init**: `client: LLMClient`, `model: String`, `instructions: String? = nil`, `tools: [FunctionToolParam] = []`, `toolChoice: ToolChoice? = nil`, `toolHandlers: [String: ToolSession.ToolHandler] = [:]`, `config: [ResponseConfigParameter] = []`, `maxToolIterations: Int = 10`
- **Declarative init**: `client: LLMClient`, `model: String`, `maxToolIterations: Int = 10`, `@SessionBuilder configure: () -> [SessionComponent]`
- **Methods**: `send(_:) -> String`, `run(_:) -> String` (alias), `reset()`
- **Properties**: `lastResponseId: String?`, `transcript: [TranscriptEntry]`, `registeredToolNames: [String]`, `toolCount: Int`

### TranscriptEntry (enum)
- **Cases**: `userMessage(String)`, `assistantMessage(String)`, `toolCall(name:arguments:)`, `toolResult(name:result:duration:)`, `error(String)`

### AgentTool (struct)
Pairs a `FunctionToolParam` definition with its handler closure.

- **Fields**: `tool: FunctionToolParam`, `handler: ToolSession.ToolHandler`

### AgentToolBuilder (result builder)
Declarative syntax for registering tools with Agent.

---

## Modified Types

| Type | Change |
|------|--------|
| `ResponseRequest` | Add `toolChoice: ToolChoice?`, `tools: [FunctionToolParam]?` fields |
| `LLMError` | Add `maxIterationsExceeded`, `unknownTool`, `toolExecutionFailed` |
| `ResponseObject` | Add `firstFunctionCalls`, `requiresToolExecution` |
