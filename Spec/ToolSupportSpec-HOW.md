# Tool Support — Implementation Details

Public API spec: [ToolSupportSpec.md](ToolSupportSpec.md)

---

## File Structure

```
Sources/SwiftOpenResponsesDSL/
├── SwiftOpenResponsesDSL.swift     # Core types, items, request/response, LLMClient
├── ToolSession.swift                # SessionComponent, SessionBuilder, ToolSession, ToolSessionResult, ToolCallLogEntry
├── Agent.swift                      # Agent actor, AgentTool, AgentToolBuilder, TranscriptEntry
```

## Key Implementation Decisions

1. **JSONSchema via macros package**: Use `JSONSchemaValue` from `SwiftLLMToolMacros` via typealias, same as Chat Completions project.

2. **ToolSession is a struct**: Stateless — takes inputs, produces outputs. `LLMClient` (actor) handles thread safety.

3. **Agent is an actor**: Manages mutable `lastResponseId` for conversation continuity; thread-safe by design.

4. **Parallel tool execution**: `withThrowingTaskGroup` when API returns multiple function calls.

5. **ToolHandler signature**: `@Sendable (String) async throws -> String` — raw JSON args in, string result out.

6. **Duplicate tool detection**: `ToolSession` and `Agent` (explicit init) use `precondition`. `Agent` declarative init throws `LLMError.invalidValue`.

7. **Tool loop accumulates full history**: Each iteration appends the model's function call items (`.functionCall`) and the corresponding results (`.functionCallOutput`) to `currentInput`, so the next request always carries the complete conversation. This differs from Chat Completions and from what `Agent` does between turns — `Agent` uses `previous_response_id` to chain separate `send()` calls, but within each turn's tool loop, full history accumulation is used.

## Tool Loop Algorithm (ToolSession)

```
1. currentInput = initial input items
2. Send request (model + currentInput + tools)
3. Receive ResponseObject
4. Check if output contains FunctionCallItem(s)
   - If no: return ToolSessionResult
   - If yes: continue
5. Execute all function call handlers in parallel
6. For each FunctionCallItem: append .functionCall(call) to currentInput
7. For each result: append .functionCallOutput(callId, result) to currentInput
8. Increment iteration count, check max
9. Send new request (model + currentInput + tools), go to step 3
```

## Streaming Tool Loop Algorithm (ToolSession.stream)

```
1. currentInput = initial input items; iteration = 0
2. Yield .iterationStarted(iteration + 1)
3. Build streaming request (model + currentInput + tools + stream: true)
4. Stream LLM response, yielding .llm(event) for every SSE event
   - Collect FunctionCallItem from .outputItemDone events
   - Capture ResponseObject.Usage from .responseCompleted
5. Yield .usageUpdate(usage, iteration + 1) if usage present
6. If no function calls collected: finish stream, return
7. Check iteration < maxIterations, else throw .maxIterationsExceeded
8. For each function call: yield .toolCallStarted(callId, name, arguments)
9. Execute all handlers in parallel via withThrowingTaskGroup
   - Each completion yields .toolCallCompleted(callId, name, output, duration)
10. Append .functionCall and .functionCallOutput items to currentInput
11. iteration += 1, go to step 2
```

## SSE Event Parsing Algorithm

The Responses API uses `event:` + `data:` pairs (not just `data:` lines like Chat Completions):

```
event: response.created
data: {"id": "resp_...", ...}

event: response.output_item.added
data: {"type": "message", ...}

event: response.content_part.delta
data: {"delta": "Hello", ...}

event: response.completed
data: {"id": "resp_...", ...}
```

Parser algorithm:
1. Read lines from SSE stream
2. For each line:
   - If starts with `event: `: store event type
   - If starts with `data: `: parse JSON data, combine with stored event type to produce StreamEvent
   - If empty line: reset event type
3. Map event type + data to StreamEvent enum cases

## Core Types Location

| Type | Kind | Location |
|------|------|----------|
| `InputItem` | enum | SwiftOpenResponsesDSL.swift |
| `OutputItem` | enum | SwiftOpenResponsesDSL.swift |
| `FunctionCallItem` | struct | SwiftOpenResponsesDSL.swift |
| `FunctionCallOutputItem` | struct | SwiftOpenResponsesDSL.swift |
| `ToolChoice` | enum | SwiftOpenResponsesDSL.swift |
| `ToolChoiceParam` | struct | SwiftOpenResponsesDSL.swift |
| `FunctionToolParam` | struct | SwiftOpenResponsesDSL.swift |
| `SessionComponent` | enum | ToolSession.swift |
| `SessionBuilder` | result builder | ToolSession.swift |
| `ToolSessionEvent` | enum | ToolSession.swift |
| `ToolSession` | struct | ToolSession.swift |
| `ToolSessionResult` | struct | ToolSession.swift |
| `ToolCallLogEntry` | struct | ToolSession.swift |
| `Agent` | actor | Agent.swift |
| `AgentTool` | struct | Agent.swift |
| `AgentToolBuilder` | result builder | Agent.swift |
| `TranscriptEntry` | enum | Agent.swift |

## Macros Bridge

`FunctionToolParam.init(from: ToolDefinition)` maps:
- `definition.name` -> `name`
- `definition.description` -> `description`
- `definition.parameters` -> `parameters` (via JSONSchema typealias)
- `type` defaults to `"function"`

`AgentTool.init<T: LLMTool>(_ instance: T)`:
1. Gets `T.toolDefinition`
2. Creates a `FunctionToolParam` from the definition
3. Creates a handler closure that decodes arguments and calls `instance.call(arguments:)`
