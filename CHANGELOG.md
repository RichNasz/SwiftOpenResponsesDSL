# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
