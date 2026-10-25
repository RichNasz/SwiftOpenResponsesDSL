# Live testing

Live tests exercise the implemented client against a local Open Responses server. `Spec/SwiftOpenResponsesDSL.md` defines the API. This file defines which of that API the live suite must call.

Not every inference server that has a Responses API implements the full Open Responses specification. The fields this suite treats loosely are optional in that spec. See [Optional spec elements](SwiftOpenResponsesDSL.md#optional-spec-elements). This suite is the example. The default server is LM Studio. It accepts the calls and returns a decoded `ResponseObject`, and the rules below record where it omits, rewrites, or rejects those optional fields. A nil echo or an allowed `serverError` is that server's limit. `decodingFailed` and `networkError` are client failures.

WebSocket transport and context compaction (`POST /v1/responses/compact`) are optional Open Responses additions and are not implemented. See [Not implemented](SwiftOpenResponsesDSL.md#not-implemented). The live suite does not open a socket or call that endpoint. LM Studio's documented Responses surface is HTTP `POST /v1/responses`, which matches that deferral. Stream and output cases the client can decode but a cooperative local model cannot be required to emit — refusal, URL citation, `queued`, `incomplete`, and `failed` — stay in the unit tests.

## Default server

`swift test` runs `LiveTests` against a local server. The suite is skipped only when that server does not answer.

| Setting | Default | Override |
|---|---|---|
| Base URL | `http://127.0.0.1:1234` | `OPENRESPONSES_BASE_URL` |
| Endpoint | `{base}/v1/responses` | — |
| Model | `openai/gpt-oss-20b` | `OPENRESPONSES_MODEL` |
| Reasoning model | the model above | `OPENRESPONSES_REASONING_MODEL` |
| API key | `not-needed` | — |

The base URL is the server root, not the `/v1/responses` path. Before the suite starts, the test POSTs `{}` to the endpoint with a 2-second timeout. Any HTTP response means the server is up. No response disables the suite with the message `Requires local LLM server`.

Tests run serialized in one suite. Each request sets `RequestTimeout(240)` unless a test says otherwise.

Rules for the default LM Studio server:

- A call must return a decoded response, unless the row allows `LLMError.serverError`. `decodingFailed` and `networkError` always fail.
- When a row names an echoed field, a non-nil echo must equal the sent value. A nil echo does not fail. LM Studio omits `safety_identifier` and `prompt_cache_key`.
- LM Studio rewrites `frequency_penalty: 0` and may report `service_tier` as `default` when `auto` was sent. Do not require those two echoes to equal the sent value.
- LM Studio rejects `item_reference` and object forms of `tool_choice` (`function`, `allowed_tools`) with HTTP 400. Those tests pass on `serverError` or on a decoded response.
- LM Studio ignores `text.format` on the echo and may return `logprobs: []`. Do not require the echoed format type or a non-empty logprobs array. `top_logprobs` is echoed.

## Existing coverage

These tests stay, and they use the defaults in the table above.

| Test | What it calls |
|---|---|
| `basicTextSend` | String `input`. Asserts `completed`, a non-empty id, non-empty `firstOutputText`, and `usage.totalTokens > 0`. |
| `structuredInput` | `System` and `User`. The text contains `4`. |
| `conversationContinuity` | `PreviousResponseId` from the first response. The second text contains `TestBot`. |
| `streaming` | `stream: true`. At least one `contentPartDelta`. `responseCompleted` or `outputItemDone`. |
| `toolSessionStreamingBasic` | `ToolSession.stream` with no tools. `iterationStarted(1)` and a content delta. No tool events. |
| `toolSessionStreamingWithTools` | `FunctionToolParam` `get_current_time`, handler returns `12:00 PM`. Asserts the tool started, completed with that output, and a second iteration. This is the live `FunctionOutput` path. |
| `agentStreaming` | `Agent.stream` with that tool. Asserts tool transcript entries and a content delta. |
| `toolSessionRunUsageAggregation` | `ToolSession.run` with that tool. `iterationUsages` is non-empty and `totalUsage.totalTokens > 0`. |
| `agentSendUsage` | `Agent.send` with that tool. `lastUsage.totalTokens > 0`. |
| `reasoningNonStreaming` | `Reasoning(effort: .low, summary: .concise)` on the reasoning model. A reasoning output item and `reasoningTokens > 0`. |
| `reasoningStreaming` | The same request with `stream: true`. A content delta or `responseCompleted`. A reasoning stream event, or a reasoning item on `responseCompleted`. LM Studio puts reasoning on the completed response and does not emit reasoning deltas. |
| `maxOutputTokens` | `MaxOutputTokens(50)`. `usage.outputTokens <= 60`. |

## Required additional calls

Each row is one live test. The prompt may be short. The response must decode, and `status` must be `completed` unless the row says otherwise.

| Test | Send | Assert |
|---|---|---|
| `developerMessage` | `Developer` plus `User` | Non-empty output text |
| `assistantPhaseFollowUp` | A completed reply, then `Assistant(text, phase: .finalAnswer, id:)` plus a `User` follow-up | Second response decodes. `phase` on the sent item is `final_answer` |
| `itemReference` | A completed reply, then `ItemReference` of the first output item id plus a `User` follow-up | Second response decodes, or `serverError` |
| `samplingParameters` | `Temperature(0)`, `TopP(1)`, `FrequencyPenalty(0)`, `PresencePenalty(0)` | Echoed `temperature` is `0`, `topP` is `1`, and `presencePenalty` is `0`. `frequencyPenalty` may differ |
| `instructions` | `Instructions("Reply with the single word pong.")` | Echoed `instructions` matches. Output text contains `pong` |
| `requestOptions` | `TruncationParam(.auto)`, `ServiceTierParam(.auto)`, `Metadata(["suite": "live"])`, `Store(false)`, `Background(false)` | Echoed `truncation`, `metadata`, `store`, and `background` match. `serviceTier` is non-nil |
| `safetyAndCache` | `SafetyIdentifier("live-user")`, `PromptCacheKey("live-cache")` | Response decodes. A non-nil echo must match the sent value |
| `logprobs` | `TopLogprobs(2)`, `IncludeParam(["message.output_text.logprobs"])` | Echoed `topLogprobs` is `2`. An empty `logprobs` array is valid |
| `jsonObjectFormat` | `TextConfig` with `TextFormat.jsonObject`. Ask for a JSON object `{"n":1}` | Output text contains `{`. Echoed format type may stay `text` |
| `jsonSchemaFormat` | `TextConfig` with `TextFormat.jsonSchema(name: "answer", schema: object with required string `answer`, strict: true, description: "A one-word answer")` | Output text is non-empty. Echoed format type may stay `text` |
| `streamOptions` | `stream: true` and `StreamOptions(includeObfuscation: false)` | At least one `contentPartDelta` and one `outputTextDelta` whose `itemId` is non-empty. No `.error` event |
| `toolChoiceNone` | The time tool and `ToolChoiceParam(.none)`. Ask for the time in prose | No `function_call` output item. Non-empty text |
| `toolChoiceFunction` | The time tool and `ToolChoiceParam(.function("get_current_time"))` | A `function_call` named `get_current_time`, or `serverError` when the server only accepts `none`, `auto`, and `required` |
| `toolChoiceRequired` | The time tool and `ToolChoiceParam(.required)` | A `function_call` output item |
| `toolChoiceAllowed` | The time tool and `ToolChoiceParam(.allowedTools(mode: .auto, tools: ["get_current_time"]))`. Ask the model to use the tool | A `function_call` named `get_current_time`, or `serverError` when the server rejects object `tool_choice` |
| `parallelToolCallsOff` | Two function tools and `ParallelToolCalls(false)` | Response decodes |
| `maxToolCallsOne` | Two function tools and `MaxToolCalls(1)`. Ask the model to call both | `function_call` output items count is `<= 1` |
| `resourceTimeout` | `ResourceTimeout(240)` and `RequestTimeout(30)` on a one-word prompt | Non-empty output text |
| `customHeader` | `LLMClient` created with `customHeaders: ["X-Live-Test": "1"]` | Non-empty output text |
| `imageInput` | `UserImage` with a 1×1 PNG data URL, `detail: "low"`, plus `User` | A decoded response, or `LLMError.serverError` when the model has no vision. `decodingFailed` and `networkError` fail the test |

`parallelToolCallsOff` does not require the model to refuse a second call. `maxToolCallsOne` does require the server to honor the cap. `imageInput` passes on a decoded response or `serverError`.
