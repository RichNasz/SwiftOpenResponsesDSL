# Open Responses surfaces this package does not implement

## What this page is

This page lists Open Responses functionality that SwiftOpenResponsesDSL does not implement. The client contract for what the package does implement is [`SwiftOpenResponsesDSL.md`](SwiftOpenResponsesDSL.md).

Checked 2026-10-25 against [Open Responses](https://www.openresponses.org/specification) spec version 2026-04-24, using [`openapi.json`](https://www.openresponses.org/openapi/openapi.json) `info.version` `2026-04-24` and the [reference](https://www.openresponses.org/reference).

## Three kinds of gap

Keep these apart.

- **Package gap.** This client cannot send, call, or faithfully decode the surface. That is the rest of this page.
- **Server gap.** This client sends and decodes the field. A host may omit, rewrite, or reject it. LM Studio is the example in [Server compatibility](SwiftOpenResponsesDSL.md#server-compatibility) and [`LiveTesting.md`](LiveTesting.md).
- **Not in Open Responses.** The 2026-04-24 OpenAPI file has two operations: `POST /responses` (HTTP, plus an optional WebSocket on the same path) and `POST /responses/compact`. `ResponsesToolParam` is only a function tool. These OpenAI Responses features are absent from that file, so they are not gaps in this package: response retrieve, cancel, and delete; the conversations API; hosted tools; audio input; MCP; `file_id`.

`application/x-www-form-urlencoded` appears in the reference. The specification says clients MUST send `application/json`. This client sends JSON. That is the required encoding, not a gap.

## Not implemented

`LLMClient` speaks HTTP `POST` to the caller-supplied `/v1/responses` URL, with JSON or server-sent events. A caller cannot reach the surfaces below through this package.

### Transport

| Surface | Spec name | What a caller does today |
|---|---|---|
| WebSocket transport, including `response.create`, sequential turns, continuation, the 60-minute connection limit, and the WebSocket `error` envelope (`status` plus `error.code`) | `WS /v1/responses`, `WebSocketResponseCreateEvent`, `WebSocketErrorEvent` | Stream with HTTP SSE |

WebSocket is optional. The specification says servers MAY expose `/v1/responses` as a socket. HTTP remains the required transport. Checked 2026-10-25, uptake outside OpenAI is still thin. The [compliance suite](https://www.openresponses.org/compliance) keeps its WebSocket tests CLI-only. LM Studio, Ollama, and vLLM document HTTP `POST /v1/responses` and do not document this socket. vLLM's separate Realtime API at `/v1/realtime` is not this transport. OpenAI documents WebSocket mode for its own Responses API. Revisit this when a server this package is tested against, starting with the LM Studio host in [`LiveTesting.md`](LiveTesting.md), documents and answers the socket.

### Compaction

| Surface | Spec name | What a caller does today |
|---|---|---|
| Context compaction | `POST /v1/responses/compact`, `CompactResponseMethodPublicBody`, `CompactResource` (`object: "response.compaction"`) | Send a shorter `input` |
| Compaction item, as input or output | `CompactionSummaryItemParam`, `CompactionBody` (`type: "compaction"`, `encrypted_content`, optional `created_by`) | No type. An output item of this type fails the whole `output` decode. See [Decoded narrowly](#decoded-narrowly). |

This endpoint is optional relative to `POST /v1/responses`. It returns a compacted conversation, not a response id. A later turn would send that window as `input`. The compliance suite includes HTTP compaction tests, and OpenAI's API implements `responses.compact`. LM Studio's published endpoint list has `POST /v1/responses` and no `/v1/responses/compact`. Ollama and vLLM document the HTTP create route and do not document compaction. Revisit this on the same terms as WebSocket.

### Input items and content

| Surface | Spec name | What a caller does today |
|---|---|---|
| Reasoning item as input | `ReasoningItemParam` (`summary`, `content`, `encrypted_content`) | `ReasoningItem` is decode-only. `include: ["reasoning.encrypted_content"]` can request the blob, and the client stores it on the output item. Nothing encodes that item onto a later turn. |
| Video input | `InputVideoContent` (`video_url`) | No content part |
| Assistant refusal as input, and citations on resent assistant text | `RefusalContentParam`; `OutputTextContentParam.annotations` | `Assistant` encodes one `output_text` part with `type` and `text` only |

Message roles `system`, `user`, `developer`, and `assistant` are implemented. So are `input_text`, `output_text`, `input_image`, `input_file` (`filename`, `file_data`, `file_url` on `InputFileContentParam`), `item_reference`, and a `function_call` item sent back as input. Reasoning configuration and reasoning output are implemented. Sending the reasoning item back is not. An `input_file` part on an output message is still not decoded. See [Decoded narrowly](#decoded-narrowly).

### Tool results

| Surface | Spec name | What a caller does today |
|---|---|---|
| Tool result that is not a string | `FunctionCallOutputItemParam.output` as an array of `input_text`, `input_image`, `input_file`, or `input_video`; optional `id` and `status` on that item | `FunctionOutput` sends `call_id` plus a string |

Function tools and `tool_choice` (`auto`, `none`, `required`, a named function, and `allowed_tools`) are implemented. The OpenAPI tool union does not add hosted tools.

## Decoded narrowly

These shapes can appear in a response or stream. The client does not model them. Unknown keys on a type the client does decode are ignored. Unknown types are not.

- An unknown `output` item type throws `DecodingError`. That includes `type: "compaction"` and a provider extension such as `openai:web_search_call`. The specification says portable clients ignore extension items. This client does not. One unknown item fails the whole `output` array.
- An output message whose content part is not `output_text` or `refusal` throws. The `Message.content` union also allows `input_text`, `text`, `summary_text`, `reasoning_text`, `input_image`, `input_file`, and `input_video`.
- A `function_call_output` item inside `output` is decoded as `FunctionCallItem`, which requires `name` and `arguments`. The spec type is `FunctionCallOutput` (`id`, `call_id`, `output`, `status`). That shape does not decode.
- A streaming `error` event keeps `error.message` only. `type`, `code`, `param`, and `headers` are dropped. An HTTP failure is `LLMError.serverError(statusCode:message:)`. The specification's error types (`server_error`, `invalid_request`, `not_found`, `model_error`, `too_many_requests`) are not a typed enum.
- `obfuscation` on `response.output_text.delta`, `response.reasoning.delta`, `response.reasoning_summary_text.delta`, and `response.function_call_arguments.delta` is not surfaced. It is optional padding.

Streaming event names the client already maps are implemented. That includes `response.reasoning_summary_part.added` and `response.reasoning_summary_part.done`.

## Maintenance

When [`openapi.json`](https://www.openresponses.org/openapi/openapi.json) `info.version` changes, update this page in the same change as [`SwiftOpenResponsesDSL.md`](SwiftOpenResponsesDSL.md). A schema from that file is either described in the client spec or named here. Enums and streaming-event schemas count as described when the client spec already names the JSON values or event names they wrap. A field the client spec describes under its JSON name is implemented even when this page does not repeat the OpenAPI identifier.
