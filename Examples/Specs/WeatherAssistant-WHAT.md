# Weather Assistant — WHAT Spec

## Overview

A conversational weather assistant that provides current weather information for any city. Users interact via a multi-turn chat interface with streaming responses.

## Model

- Model: `gpt-4o` (or any Open Responses API-compatible model)
- No reasoning model required

## Tools

### get_weather

| Argument | Type | Required | Constraints | Description |
|---|---|---|---|---|
| `location` | String | Yes | — | City and optional state/country, e.g. "Paris, France" |
| `unit` | String | No | One of: "celsius", "fahrenheit" | Temperature unit preference |

**Returns:** JSON string with `temperature`, `condition`, and `location` fields.

## Conversation Requirements

- Multi-turn: users ask follow-up questions that reference earlier context (e.g., "How about London?" after asking about Paris)
- System instruction: "You are a helpful weather assistant. Use the get_weather tool to answer weather questions."
- The assistant should automatically call the tool when the user asks about weather

## Streaming Requirements

- Responses must stream in real-time to the user
- Tool call activity (started/completed) should be surfaced to the UI
- Token usage should be tracked per response

## Error Handling

- Rate limiting: retry with backoff
- Network errors: inform the user
- Tool failures: report gracefully

## Acceptance Criteria

- [ ] User can ask about weather in any city and get a response
- [ ] User can ask follow-up questions that reference prior context
- [ ] Responses stream token-by-token to the UI
- [ ] Tool calls are visible in the UI (started/completed)
- [ ] Token usage is tracked
- [ ] Errors are handled gracefully without crashing
- [ ] Code compiles with `swift build`
