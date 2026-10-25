# ``SwiftOpenResponsesDSL``

A Swift DSL for the Open Responses API.

## Overview

A domain-specific language (DSL) is a small API shaped for one problem. SwiftOpenResponsesDSL is an embedded DSL: result builders and typed values stand in for the JSON of an Open Responses request.

The Open Responses API is a shared format for text generation, tools, and streaming. This package calls it over HTTP. `send` returns one JSON ``ResponseObject``. `stream` reads server-sent events as ``StreamEvent`` values.

Text inference from Open Responses 2026-04-24 is included: `top_logprobs`, `safety_identifier`, `prompt_cache_key`, `stream_options`, assistant message `phase`, output-text logprobs, and the text streaming events (`output_text.done`, refusal, annotation, reasoning text, and reasoning-summary text).

Some of those fields are optional in the Open Responses specification. A server may omit assistant `phase`, output-text `logprobs`, and the other request configuration fields. This client still sends the optional HTTP fields you set, and it accepts a response that leaves them out. The full split of required and optional elements is in [Spec/SwiftOpenResponsesDSL.md](../../../Spec/SwiftOpenResponsesDSL.md).

`swift test` exercises the client against LM Studio at `http://127.0.0.1:1234` with model `openai/gpt-oss-20b`. That server answers and still skips part of the optional surface: it can omit `safety_identifier` and `prompt_cache_key`, rewrite `frequency_penalty` and `service_tier`, reject `item_reference` and object `tool_choice` with HTTP 400, ignore JSON `text.format`, return empty `logprobs`, and put reasoning on the completed response without reasoning deltas.

Streaming examples in this documentation are HTTP server-sent events. The package does not cover every Open Responses surface. WebSocket transport, context compaction (`POST /v1/responses/compact`), video input, reasoning-item round-trip, and non-string tool output are not implemented. Unknown output item types fail decoding. They are not ignored. The inventory is [Spec/Unimplemented.md](../../../Spec/Unimplemented.md).

## Topics

### Client

- ``LLMClient``
- ``ResponseRequest``
- ``ResponseObject``
- ``StreamEvent``

### Text inference

- ``AssistantPhase``
- ``TopLogprobs``
- ``SafetyIdentifier``
- ``PromptCacheKey``
- ``StreamOptions``
- ``LogProb``
- ``OutputTextContent``
