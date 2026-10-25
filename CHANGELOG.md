# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- File input encoding: `UserFile` and `InputContentPart.inputFile` send `InputFileContentParam` (`filename`, `file_data`, `file_url`). Nil fields are omitted. An `input_file` part on an output message still fails decoding.
- `LLMClient.prewarm()` sends `GET` on the client's own session and returns after the request starts. Open Responses has no prewarm operation.
- Text inference fields from Open Responses 2026-04-24: `top_logprobs`, `safety_identifier`, `prompt_cache_key`, `stream_options`, assistant message `phase`, output-text logprobs, and the text streaming events (`output_text.done`, refusal, annotation, reasoning text, reasoning summary text).
- Live tests call the implemented API against a local server. The default model is `openai/gpt-oss-20b` at `http://127.0.0.1:1234`. LM Studio is the example of a Responses server that does not implement the full spec: omitted or rewritten echoes, HTTP 400 on some fields, ignored JSON format, empty logprobs, and reasoning without reasoning deltas.

### Changed

- `Spec/Unimplemented.md` lists the Open Responses 2026-04-24 functionality this package does not implement, including WebSocket transport, compaction, video input, reasoning-item round-trip, and non-string tool output. Unknown output item types fail decoding. See that page. Optional HTTP fields this package does implement may still be omitted by a server. See `Spec/SwiftOpenResponsesDSL.md`.

## [0.2.0] - 2026-06-12

Initial tagged release.

### Added

- Core types: `InputItem`, `OutputItem`, `ResponseRequest`, `ResponseObject`
- `LLMClient` actor with streaming and non-streaming support
- `ToolSession` with automatic tool-calling loop (accumulates conversation history)
- `Agent` actor with `previous_response_id`-based conversation continuity
- Result builders: `@InputBuilder`, `@ResponseConfigBuilder`, `@SessionBuilder`
- Streaming via `AsyncThrowingStream<StreamEvent, Error>` with semantic events
- Reasoning support: `ReasoningItem`, `ReasoningSummary`, reasoning streaming events
- Token usage tracking on `ToolSessionResult`, `ToolSessionEvent`, and `Agent`
- Config parameters: `Store`, `Background`, `MaxToolCalls`, `TextConfig`, `Reasoning`
- `include` parameter for `ResponseRequest`
- Custom HTTP headers support on `LLMClient`
- `FunctionToolParam(from: ToolDefinition)` bridge for `@LLMTool` macro integration
- `AgentTool<T: LLMTool>` bridge initializer

### Fixed

- `InputContentPart.inputImage` encoding to match Open Responses spec
- Stream parser to unwrap response objects from SSE event wrappers
- `ToolSession` accumulates full conversation history instead of relying on `previous_response_id`
