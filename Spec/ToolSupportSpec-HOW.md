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

7. **Tool loop uses `previous_response_id`**: Instead of re-sending full message history, each iteration sends only the new `function_call_output` items plus `previous_response_id` pointing to the last response. This is the key architectural difference from Chat Completions.

## Tool Loop Algorithm (ToolSession)

```
1. Send initial request (model + input items + tools)
2. Receive ResponseObject
3. Check if output contains FunctionCallItem(s)
   - If no: return response as final result
   - If yes: continue
4. Execute all function call handlers in parallel
5. Build new request:
   - model: same model
   - previous_response_id: response.id
   - input: [FunctionCallOutputItem(callId, result) for each function call]
   - tools: same tools
6. Increment iteration count, check max
7. Go to step 2
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

`AgentTool.init<T: ChatCompletionsTool>(_ instance: T)`:
1. Gets `T.toolDefinition`
2. Creates a `FunctionToolParam` from the definition
3. Creates a handler closure that decodes arguments and calls `instance.call(arguments:)`
