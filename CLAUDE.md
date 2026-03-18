# SwiftOpenResponsesDSL

## Architecture

SwiftOpenResponsesDSL is an embedded Swift DSL for the [Open Responses API](https://www.openresponses.org/) — a multi-provider, interoperable LLM interface specification.

### Key Differences from SwiftChatCompletionsDSL
- **Input model**: `[InputItem]` (polymorphic enum) instead of `[any ChatMessage]` (flat array)
- **Output model**: `output[]` (polymorphic items) instead of `choices[].message`
- **Conversation continuity**: `previous_response_id` instead of re-sending full message history
- **Roles**: system, user, assistant, developer (no `tool` role)
- **Max tokens**: `max_output_tokens` instead of `max_tokens`
- **Streaming**: `event:` + `data:` pairs with semantic events instead of raw deltas

### File Structure
- `Sources/SwiftOpenResponsesDSL/SwiftOpenResponsesDSL.swift` — Core types, items, request/response, LLMClient
- `Sources/SwiftOpenResponsesDSL/ToolSession.swift` — SessionComponent, SessionBuilder, ToolSession, ToolSessionResult
- `Sources/SwiftOpenResponsesDSL/Agent.swift` — Agent actor, AgentTool, AgentToolBuilder, TranscriptEntry

### Design Patterns
- **Result builders**: `@InputBuilder` for input items, `@ResponseConfigBuilder` for config, `@SessionBuilder` for mixed items+tools
- **Actor-based client**: `LLMClient` is an actor for thread safety
- **Protocol-based config**: `ResponseConfigParameter` protocol with `apply(to:)` method
- **Polymorphic items**: `InputItem` and `OutputItem` enums with type discriminators

### Tool Loop (Key Architecture)
Uses `previous_response_id` instead of re-sending history:
1. Send initial request (model + input + tools)
2. If response contains function calls, execute handlers in parallel
3. Send new request with only `function_call_output` items + `previous_response_id`
4. Repeat until no more function calls

### Dependencies
- `SwiftChatCompletionsMacros` — JSONSchema types and `@ChatCompletionsTool` macro support

### Build & Test
```bash
swift build
swift test
```
