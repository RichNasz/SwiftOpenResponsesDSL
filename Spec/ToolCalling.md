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

### ToolSessionEvent (enum)
Events emitted during a streaming ToolSession run.

- **Cases**: `iterationStarted(Int)`, `llm(StreamEvent)`, `toolCallStarted(callId:name:arguments:)`, `toolCallCompleted(callId:name:output:duration:)`, `usageUpdate(ResponseObject.Usage, iteration: Int)`
- **Conformance**: `Sendable`

### ToolSession (struct)
Orchestrates the tool-calling loop by accumulating full conversation history across iterations.

- **ToolHandler**: `@Sendable (String) async throws -> String`
- **Explicit init**: `client: LLMClient`, `tools: [FunctionToolParam]`, `toolChoice: ToolChoice? = nil`, `maxIterations: Int = 10`, `handlers: [String: ToolHandler]`
- **Declarative init**: `client: LLMClient`, `model: String`, `toolChoice: ToolChoice? = nil`, `maxIterations: Int = 10`, `@SessionBuilder configure: () -> [SessionComponent]`
- **run(model:input:config:)**: Accepts model, input items, config; returns `ToolSessionResult`
- **run(model:input:configParams:)**: Accepts pre-computed `[ResponseConfigParameter]`; returns `ToolSessionResult`
- **run(_ prompt:)**: Shorthand for declarative init
- **stream(model:input:configParams:)**: Returns `AsyncThrowingStream<ToolSessionEvent, Error>`
- **stream(_ prompt:)**: Streaming shorthand for declarative init

Key difference from Chat Completions: The tool loop accumulates full conversation history in `currentInput` across iterations — appending `.functionCall` and `.functionCallOutput` items each round-trip — rather than using `previous_response_id`.

### ToolSessionResult (struct)
- **Fields**: `response: ResponseObject`, `iterations: Int`, `log: [ToolCallLogEntry]`, `iterationUsages: [ResponseObject.Usage]`
- **Computed**: `totalUsage: ResponseObject.Usage?` — aggregates all iteration usages; `nil` if no iteration included usage

### ToolCallLogEntry (struct)
- **Fields**: `name: String`, `arguments: String`, `result: String`, `duration: Duration`

### Agent (actor)
High-level persistent agent with `lastResponseId` for conversation continuity between turns.

- **Explicit init**: `client: LLMClient`, `model: String`, `instructions: String? = nil`, `tools: [FunctionToolParam] = []`, `toolChoice: ToolChoice? = nil`, `toolHandlers: [String: ToolSession.ToolHandler] = [:]`, `config: [ResponseConfigParameter] = []`, `maxToolIterations: Int = 10`
- **Builder init**: `client: LLMClient`, `model: String`, `instructions: String? = nil`, `maxToolIterations: Int = 10`, `@ResponseConfigBuilder config: () throws -> [ResponseConfigParameter]`, `@AgentToolBuilder tools: () -> [AgentTool]`
- **SessionBuilder init**: `client: LLMClient`, `model: String`, `maxToolIterations: Int = 10`, `@SessionBuilder configure: () -> [SessionComponent]`
- **Methods**: `send(_:) -> String`, `run(_:) -> String` (alias), `stream(_:) -> AsyncThrowingStream<ToolSessionEvent, Error>`, `reset()`
- **Properties**: `lastResponseId: String?`, `lastUsage: ResponseObject.Usage?`, `transcript: [TranscriptEntry]`, `registeredToolNames: [String]`, `toolCount: Int`

### TranscriptEntry (enum)
- **Cases**: `userMessage(String)`, `assistantMessage(String)`, `reasoning(ReasoningItem)`, `toolCall(name:arguments:)`, `toolResult(name:result:duration:)`, `error(String)`
- Transcript ordering per turn: `userMessage → reasoning(item)... → assistantMessage`, mirroring API output order.

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
