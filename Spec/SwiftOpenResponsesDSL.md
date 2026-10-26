# Specification for SwiftOpenResponsesDSL

## Overview
The **SwiftOpenResponsesDSL** is an embedded Swift DSL that provides direct access to [Open Responses API](https://www.openresponses.org/) endpoints. It abstracts HTTP requests, JSON serialization, authentication, and error handling into a declarative, type-safe interface, supporting both non-streaming and streaming responses. Other packages may reference this package to build higher-level integrations. Users must provide the complete endpoint URL (`baseURL`) when initializing the client and the `model` in every request, ensuring compatibility with varied servers (e.g., `https://api.openai.com/v1/responses`, `https://your-server.com/v1/responses`). Optional parameters are specified via a `@ResponseConfigBuilder` block, allowing users to include only desired parameters with minimal code.

The Open Responses API differs from Chat Completions by using an item-based model with polymorphic input/output types, `previous_response_id` for conversation continuity, semantic streaming events, and built-in reasoning support.

For tool calling and agent capabilities, see [ToolCalling.md](ToolCalling.md) and [ToolSupportSpec.md](ToolSupportSpec.md).

## Goals
- **Explicit Configuration**: Require `baseURL` (full endpoint URL) in client initialization and `model` in every request, without defaults or path appending.
- **Optional Parameters**: Allow any combination of optional parameters via a `@ResponseConfigBuilder` block, minimizing user code while ensuring type safety.
- **Declarative API**: Use result builders for input items (`@InputBuilder`) and configuration (`@ResponseConfigBuilder`), supporting control flow (e.g., `if`, `for`).
- **Polymorphic Items**: Support the Responses API's item-based model with typed enums for input and output items.
- **Type Safety**: Enforce roles, parameters, and responses at compile time using enums, protocols, and structs.
- **Concurrency**: Use `async`/`await` and actors for non-blocking calls; apply `nonisolated` for streaming method flexibility.
- **Performance**: Use value types (structs) and compile-time transformations (e.g., result builders) to minimize runtime overhead.
- **Error Handling**: Propagate errors with a custom error enum using `throws`.

## Requirements
- **Spec authority**: Files in `Spec/` are the source of truth for this package. Update the relevant spec before changing code, and implement only what that spec describes. The Open Responses API (spec version 2026-04-24) informs `Spec/`, but generated code follows `Spec/`.
- **Swift Version**: 6.2+ (enable for trailing commas, `nonisolated`, improved type inference).
- **Dependencies**: SwiftLLMToolMacros (for JSONSchema and tool macros).
- **API Compatibility**: Align with Open Responses API JSON format for requests and responses (camelCase internally, snake_case in JSON via `CodingKeys`).
- **Testing**: Support Swift Testing for async validation (e.g., `#expect` with concurrency traits).
- **URL Handling**: Treat `baseURL` as the complete endpoint URL provided by the user, without modification.
- **Minimum OS Versions**: macOS 13.0, iOS 16.0.
- **Partial server support**: A Responses endpoint does not mean the server implements the full Open Responses specification. See [Server compatibility](#server-compatibility).
- **Optional spec elements**: Call out Open Responses optional transports, endpoints, and fields where they affect this client. See [Optional spec elements](#optional-spec-elements).
- **Package gaps**: Open Responses functionality this package does not implement is listed in [`Unimplemented.md`](Unimplemented.md). WebSocket transport and `POST /v1/responses/compact` are the two missing endpoints. See [Not implemented](#not-implemented).

---

## Server compatibility

Not every inference server that exposes a Responses API implements every field in this spec. The gaps below are optional Open Responses elements: the server still speaks HTTP `POST /v1/responses`, and it omits, rewrites, or rejects fields the reference marks optional. The client still encodes the request fields and decodes the response and stream events defined here. A server may accept the call, omit or rewrite an echoed optional field, reject one with HTTP 400 (`LLMError.serverError`), or skip an optional stream event the client knows how to parse. See [Optional spec elements](#optional-spec-elements).

Local testing is the example. [`LiveTesting.md`](LiveTesting.md) runs `swift test` against LM Studio at `http://127.0.0.1:1234` with model `openai/gpt-oss-20b`. That server answers the implemented calls and returns a decoded `ResponseObject`, and it does not have full spec support:

- It omits `safety_identifier` and `prompt_cache_key` on the echo.
- It rewrites `frequency_penalty: 0` and may report `service_tier` as `default` when `auto` was sent.
- It rejects `item_reference` and object forms of `tool_choice` (`function`, `allowed_tools`) with HTTP 400.
- It ignores `text.format` on the echo and may return `logprobs: []`. `top_logprobs` is echoed.
- It puts reasoning on the completed response and does not emit reasoning deltas.

A decoded response, a nil echo, or an allowed `serverError` is a limit of that server. `decodingFailed` means the payload does not match this client. `networkError` means the server did not answer.

---

## Optional spec elements

Open Responses uses RFC 2119. An element is optional when the specification says MAY or OPTIONAL, or when the [reference](https://www.openresponses.org/reference) marks the field optional. This package implements the optional HTTP fields listed below, tolerates them when a response omits them, and leaves the optional transports and the compaction endpoint unimplemented. A server that skips an optional element can still be a useful Responses server. A server that breaks the required HTTP exchange cannot.

Required for an HTTP Responses call, and implemented here:

- Request body is `application/json`. The client sends `Authorization` and `Content-Type`. The specification lists both headers as required. A local server may ignore the key. LM Studio tests use `not-needed`.
- A non-streaming response is `application/json`.
- A streaming response is `text/event-stream`. The `event` name matches the body's `type`. The stream includes a terminal event: `response.completed`, `response.failed`, or `response.incomplete`.
- The client accepts a stream that ends on that terminal event. The specification says servers MAY send `[DONE]` after it, and clients MUST accept the end with no `[DONE]`.

Optional, implemented, and safe for a server to omit or ignore:

- Assistant `phase` (`commentary` or `final_answer`) is an optional field added 2026-04-24. The client encodes it only from `Assistant(_:phase:id:)`. A missing `phase` decodes as `nil`. Some models, such as `gpt-5.3-codex`, degrade when a resent assistant message drops it. That is model behavior, not a required field.
- `logprobs` on output text and on `response.output_text.delta` / `response.output_text.done` is optional as of 2026-04-24. A missing array decodes as `nil`. An empty array is valid. `top_logprobs` and `include: ["message.output_text.logprobs"]` are optional request fields.
- Every other configuration parameter is optional on the request: sampling (`temperature`, `top_p`, `frequency_penalty`, `presence_penalty`), `truncation`, `service_tier`, `reasoning`, `store`, `background`, `max_output_tokens`, `max_tool_calls`, `text` (including JSON format and schema `description`), `stream_options`, `safety_identifier`, `prompt_cache_key`, `metadata`, `tools`, `tool_choice`, `previous_response_id`, `instructions`, and `parallel_tool_calls`. The client sends a field only when the caller sets it. A non-nil echo must match. A nil echo is allowed.
- `id` and `status` on an input message, and `detail` on `input_image`, are optional.
- `filename`, `file_data`, and `file_url` on `input_file` are optional. The client encodes each only when the caller sets it. `file_data` is a base64 string. Open Responses limits that string to 33554432 characters. This client does not enforce the limit.
- Tools, image input, file input, and reasoning are in the shared item model. A given model may still reject them with HTTP 400. The live suite allows `serverError` for vision and for object `tool_choice`.
- Provider extension item types and extra fields are optional. The specification says portable clients ignore them. Unknown keys on a type this client decodes are ignored. Unknown output item types are not: decoding `output` throws. An output message content part other than `output_text` or `refusal` also throws. See [Decoded narrowly](Unimplemented.md#decoded-narrowly).

Optional, and not implemented. The inventory is [`Unimplemented.md`](Unimplemented.md):

- WebSocket transport. The specification says servers MAY expose `/v1/responses` as a socket. HTTP remains the required transport for a Responses call.
- `POST /v1/responses/compact` and the compaction item. The specification adds them as a separate context-compression endpoint. It does not say every Responses server MUST offer them. The required create-response exchange does not include them.
- Video input, a reasoning item sent back as input, assistant refusal content on input, citations on resent assistant text, and a tool result that is not a string. File input is encoded. See `InputContentPart.inputFile`. An output message part of type `input_file` still fails decoding. See [Decoded narrowly](Unimplemented.md#decoded-narrowly).

---

## Not implemented

[`Unimplemented.md`](Unimplemented.md) is the inventory of Open Responses 2026-04-24 functionality this package does not implement. It separates those package gaps from servers that omit fields this client does send, and from OpenAI routes that are not in Open Responses.

`LLMClient` speaks HTTP `POST` to the caller-supplied `/v1/responses` URL, with JSON or SSE. It does not open a WebSocket and does not call `POST /v1/responses/compact`. Those two are optional in the specification. The uptake note, and the rest of the missing item and content model, are on that page.

---

## Core Components

### 1. Enums

- **Role**: Defines message roles for the Responses API.
  - Signature: `enum Role: String, Codable, Sendable { case system, user, assistant, developer }`
  - Purpose: Represents message roles. The Responses API uses `developer` instead of Chat Completions' `tool` role.
  - JSON: Encodes as strings (e.g., `"system"`).

- **ResponseStatus**: Status of a response.
  - Signature: `enum ResponseStatus: String, Codable, Sendable { case inProgress = "in_progress", completed, failed, incomplete, queued }`

- **ReasoningEffort**: Controls reasoning depth.
  - Signature: `enum ReasoningEffort: String, Codable, Sendable { case none, low, medium, high, xhigh }`

- **ReasoningSummaryType**: Controls reasoning summary verbosity.
  - Signature: `enum ReasoningSummaryType: String, Codable, Sendable { case concise, detailed, auto }`

- **ServiceTier**: Service tier selection.
  - Signature: `enum ServiceTier: String, Codable, Sendable { case auto, \`default\`, flex, priority }`

- **Truncation**: Truncation strategy.
  - Signature: `enum Truncation: String, Codable, Sendable { case auto, disabled }`

- **TextVerbosity**: Controls verbosity of text responses.
  - Signature: `enum TextVerbosity: String, Codable, Sendable { case low, medium, high }`

- **AssistantPhase**: Optional Open Responses field on an assistant message. Labels the message as intermediate commentary or the final answer. Follow-up requests that resend assistant text should include `phase`. Omitting it is valid in the spec and degrades models such as `gpt-5.3-codex`. Not used for user messages.
  - Signature: `enum AssistantPhase: String, Codable, Sendable { case commentary, finalAnswer = "final_answer" }`

- **ToolChoiceMode**: Mode used within `ToolChoice.allowedTools`, maps to `ToolChoiceValueEnum`.
  - Signature: `enum ToolChoiceMode: String, Codable, Sendable { case none, auto, required }`

- **LLMError**: Custom errors for API failures.
  - Signature: `enum LLMError: Error, Equatable { case invalidURL, encodingFailed(String), networkError(String), decodingFailed(String), serverError(statusCode: Int, message: String?), rateLimit, invalidResponse, invalidValue(String), missingBaseURL, missingModel, maxIterationsExceeded(Int), unknownTool(String), toolExecutionFailed(toolName: String, message: String) }`

### 2. Protocols

- **ResponseConfigParameter**: Protocol for configuration parameters.
  - Signature: `protocol ResponseConfigParameter: Sendable { func apply(to request: inout ResponseRequest) }`

### 3. Item Types

#### Input Items (polymorphic with `type` discriminator)

- **InputItem**: Polymorphic enum for input items.
  ```swift
  enum InputItem: Sendable, Encodable {
      case message(InputMessage)
      case functionCall(FunctionCallItem)
      case functionCallOutput(FunctionCallOutputItem)
      case itemReference(ItemReference)
  }
  ```
  - JSON: Encodes based on the inner type's `type` field.

- **InputMessage**: A message input item.
  ```swift
  struct InputMessage: Sendable, Encodable {
      let role: Role  // system, user, assistant, developer
      let content: InputContent
      let id: String?
      let status: String?
      let phase: AssistantPhase?
      // type is always "message"
  }
  ```
  - Encode `id`, `status`, and `phase` only when present. `phase` is for assistant messages.

- **InputContent**: Content of an input message (string or structured).
  ```swift
  enum InputContent: Sendable, Encodable {
      case text(String)
      case parts([InputContentPart])
  }
  ```

- **InputContentPart**: Individual content part.
  ```swift
  enum InputContentPart: Sendable, Encodable {
      case inputText(String)
      case outputText(String)
      case inputImage(url: String, detail: String?)
      case inputFile(filename: String?, fileData: String?, fileURL: String?)
  }
  ```
  - `inputText` encodes as `{"type": "input_text", "text": "..."}`
  - `outputText` encodes as `{"type": "output_text", "text": "..."}` and is the content part used when resending assistant text
  - `inputImage` encodes as `{"type": "input_image", "image_url": "<url>", "detail": "<detail>"}` — `image_url` is a flat string (URL or base64 data URI), `detail` is an optional sibling field (`"low"`, `"high"`, or `"auto"`)
  - `inputFile` encodes as `{"type": "input_file"}` plus any of `filename`, `file_data`, and `file_url` that are set. This is `InputFileContentParam`. A nil field is omitted. `file_data` is base64. The client does not check the 33554432-character limit. Decoding an `input_file` part on an output message is unchanged: it throws. See [Decoded narrowly](Unimplemented.md#decoded-narrowly).

- **FunctionCallOutputItem**: Result of a function call.
  ```swift
  struct FunctionCallOutputItem: Sendable, Encodable {
      let callId: String
      let output: String
      // type is always "function_call_output"
  }
  ```

- **ItemReference**: Reference to a previous item by ID.
  ```swift
  struct ItemReference: Sendable, Encodable {
      let id: String
      // type is always "item_reference"
  }
  ```

#### Output Items (polymorphic)

- **OutputItem**: Polymorphic enum for output items.
  ```swift
  enum OutputItem: Sendable, Decodable {
      case message(OutputMessage)
      case functionCall(FunctionCallItem)
      case functionCallOutput(FunctionCallItem)  // type: "function_call_output" echoed by server
      case reasoning(ReasoningItem)
  }
  ```

- **OutputMessage**: A message in the response output.
  ```swift
  struct OutputMessage: Sendable, Decodable {
      let id: String
      let role: Role
      let content: [OutputContent]
      let status: String?
      let phase: AssistantPhase?
  }
  ```
  - `phase` decodes from `"commentary"` or `"final_answer"`. Absent `phase` decodes as `nil`.

- **OutputContent**: Content of an output message.
  ```swift
  enum OutputContent: Sendable, Decodable {
      case outputText(OutputTextContent)
      case refusal(String)
  }
  ```

- **OutputTextContent**: Text content with optional annotations.
  ```swift
  struct OutputTextContent: Sendable, Decodable {
      let text: String
      let annotations: [Annotation]?
      let logprobs: [LogProb]?
  }
  ```
  - A missing `annotations` array decodes as `nil`. `logprobs` is optional in Open Responses as of 2026-04-24. A missing `logprobs` array decodes as `nil`.

- **LogProb**: One sampled token and its log probability.
  ```swift
  struct LogProb: Sendable, Decodable {
      let token: String
      let logprob: Double
      let bytes: [Int]
      let topLogprobs: [TopLogProb]  // JSON: "top_logprobs"
  }
  struct TopLogProb: Sendable, Decodable {
      let token: String
      let logprob: Double
      let bytes: [Int]
  }
  ```

- **Annotation**: Text annotation.
  ```swift
  struct Annotation: Sendable, Decodable {
      let type: String
      let startIndex: Int?
      let endIndex: Int?
      let url: String?
      let title: String?
  }
  ```

- **FunctionCallItem**: A function call in the output (also re-sent as input during tool loops).
  ```swift
  struct FunctionCallItem: Sendable, Codable {
      let id: String
      let callId: String
      let name: String
      let arguments: String
      let status: String?
  }
  ```

- **ReasoningItem**: Reasoning output item.
  ```swift
  struct ReasoningItem: Sendable, Decodable {
      let id: String
      let summary: [ReasoningSummary]?
      let content: [ReasoningContent]?
      let encryptedContent: String?
  }
  ```
  - Computed properties:
    - `summaryText: String?` — concatenated text from all summary entries joined by `"\n"`; `nil` if absent or empty
    - `contentText: String?` — concatenated text from all content entries joined by `"\n"`; `nil` if absent or empty

- **ReasoningSummary**: A summary entry in reasoning.
  ```swift
  struct ReasoningSummary: Sendable, Decodable {
      let type: String
      let text: String
  }
  ```

- **ReasoningContent**: Raw reasoning trace content (type: `"reasoning_text"`).
  ```swift
  struct ReasoningContent: Sendable, Decodable {
      let type: String   // "reasoning_text"
      let text: String
  }
  ```

### 4. Configuration Parameter Structs

Each implementing `ResponseConfigParameter`:

- **Temperature**: `init(_ value: Double) throws` — validates 0.0...2.0, sets `request.temperature`
- **TopP**: `init(_ value: Double) throws` — validates 0.0...1.0, sets `request.topP`
- **FrequencyPenalty**: `init(_ value: Double) throws` — validates -2.0...2.0, sets `request.frequencyPenalty`
- **PresencePenalty**: `init(_ value: Double) throws` — validates -2.0...2.0, sets `request.presencePenalty`
- **MaxOutputTokens**: `init(_ value: Int) throws` — validates >0, sets `request.maxOutputTokens`
- **Instructions**: `init(_ value: String) throws` — validates non-empty, sets `request.instructions`
- **PreviousResponseId**: `init(_ value: String) throws` — validates non-empty, sets `request.previousResponseId`
- **Reasoning**: `init(effort: ReasoningEffort, summary: ReasoningSummaryType? = nil)` — sets `request.reasoning`
- **TruncationParam**: `init(_ value: Truncation)` — sets `request.truncation`
- **ServiceTierParam**: `init(_ value: ServiceTier)` — sets `request.serviceTier`
- **Metadata**: `init(_ value: [String: String])` — sets `request.metadata`
- **ParallelToolCalls**: `init(_ value: Bool)` — sets `request.parallelToolCalls`
- **IncludeParam**: `init(_ values: [String]) throws` — validates non-empty, sets `request.include` (e.g. `["reasoning.encrypted_content"]`)
- **RequestTimeout**: `init(_ value: TimeInterval) throws` — validates 10...900, sets `request.requestTimeout`
- **ResourceTimeout**: `init(_ value: TimeInterval) throws` — validates 30...3600, sets `request.resourceTimeout`
- **Store**: `init(_ value: Bool)` — sets `request.store` (persist response server-side)
- **Background**: `init(_ value: Bool)` — sets `request.background` (use background execution mode)
- **MaxToolCalls**: `init(_ value: Int) throws` — validates >0, sets `request.maxToolCalls`
- **TextConfig**: `init(_ value: TextParam)` — sets `request.text` (response format and verbosity)
- **TopLogprobs**: `init(_ value: Int) throws` — validates ≥ 0, sets `request.topLogprobs` (JSON: `top_logprobs`)
- **SafetyIdentifier**: `init(_ value: String) throws` — validates non-empty, sets `request.safetyIdentifier` (JSON: `safety_identifier`)
- **PromptCacheKey**: `init(_ value: String) throws` — validates non-empty, sets `request.promptCacheKey` (JSON: `prompt_cache_key`)
- **StreamOptions**: `init(includeObfuscation: Bool)` — sets `request.streamOptions` (JSON: `stream_options.include_obfuscation`)
- **ToolChoiceParam**: `init(_ value: ToolChoice)` — sets `request.toolChoice` (controls model tool selection strategy)

### 5. Convenience Message Functions

- `System(_ content: String) -> InputItem` — creates `.message(InputMessage(role: .system, content: .text(content)))`
- `Developer(_ content: String) -> InputItem` — creates `.message(InputMessage(role: .developer, content: .text(content)))`
- `User(_ content: String) -> InputItem` — creates `.message(InputMessage(role: .user, content: .text(content)))`
- `UserImage(_ url: String, detail: String? = nil) -> InputItem` — creates `.message(InputMessage(role: .user, content: .parts([.inputImage(url: url, detail: detail)])))`
- `UserFile(filename: String? = nil, fileData: String? = nil, fileURL: String? = nil) -> InputItem` — creates `.message(InputMessage(role: .user, content: .parts([.inputFile(filename: filename, fileData: fileData, fileURL: fileURL)])))`
- `FunctionOutput(callId: String, output: String) -> InputItem` — creates `.functionCallOutput(FunctionCallOutputItem(callId: callId, output: output))`
- `Assistant(_ content: String, phase: AssistantPhase, id: String? = nil) -> InputItem` — creates an assistant message whose content is one `output_text` part, with `phase` set. Use this when resending assistant text on a later turn.

### 6. Result Builders

- **ToolsBuilder**: Composes `FunctionToolParam` arrays declaratively.
  ```swift
  @resultBuilder
  struct ToolsBuilder {
      static func buildBlock(_ components: FunctionToolParam...) -> [FunctionToolParam]
      static func buildEither(first: [FunctionToolParam]) -> [FunctionToolParam]
      static func buildEither(second: [FunctionToolParam]) -> [FunctionToolParam]
      static func buildOptional(_ component: [FunctionToolParam]?) -> [FunctionToolParam]
      static func buildArray(_ components: [[FunctionToolParam]]) -> [FunctionToolParam]
  }
  ```

- **InputBuilder**: Composes input item sequences.
  ```swift
  @resultBuilder
  struct InputBuilder {
      static func buildBlock(_ components: InputItem...) -> [InputItem]
      static func buildEither(first: [InputItem]) -> [InputItem]
      static func buildEither(second: [InputItem]) -> [InputItem]
      static func buildOptional(_ component: [InputItem]?) -> [InputItem]
      static func buildArray(_ components: [[InputItem]]) -> [InputItem]
      static func buildLimitedAvailability(_ component: [InputItem]) -> [InputItem]
  }
  ```

- **ResponseConfigBuilder**: Composes configuration parameters.
  ```swift
  @resultBuilder
  struct ResponseConfigBuilder {
      static func buildBlock(_ components: ResponseConfigParameter...) -> [ResponseConfigParameter]
      static func buildEither(first: [ResponseConfigParameter]) -> [ResponseConfigParameter]
      static func buildEither(second: [ResponseConfigParameter]) -> [ResponseConfigParameter]
      static func buildOptional(_ component: [ResponseConfigParameter]?) -> [ResponseConfigParameter]
      static func buildArray(_ components: [[ResponseConfigParameter]]) -> [ResponseConfigParameter]
      static func buildLimitedAvailability(_ component: [ResponseConfigParameter]) -> [ResponseConfigParameter]
  }
  ```

### 7. Request/Response Types

- **ResponseInput**: Represents the `input` field of a request.
  ```swift
  enum ResponseInput: Sendable, Encodable {
      case text(String)
      case items([InputItem])
  }
  ```

- **ReasoningConfig**: Reasoning configuration.
  ```swift
  struct ReasoningConfig: Sendable, Encodable {
      let effort: ReasoningEffort
      let summary: ReasoningSummaryType?
  }
  ```

- **ToolChoice**: Controls how the model selects tools.
  ```swift
  enum ToolChoice: Sendable, Equatable, Encodable {
      case auto                                         // "auto"
      case none                                         // "none"
      case required                                     // "required"
      case function(String)                             // {"type":"function","name":"..."}
      case allowedTools(mode: ToolChoiceMode, tools: [String])
      // {"type":"allowed_tools","mode":"auto","tools":[{"type":"function","name":"..."},...]}
  }
  ```

- **FunctionToolParam**: Tool definition for the Responses API.
  ```swift
  struct FunctionToolParam: Sendable, Encodable {
      let type: String  // always "function"
      let name: String
      let description: String
      let parameters: JSONSchema
      let strict: Bool?
  }
  ```

- **TextFormat**: Output format of text responses.
  ```swift
  enum TextFormat: Sendable, Encodable {
      case text                                              // {"type":"text"}
      case jsonObject                                        // {"type":"json_object"}
      case jsonSchema(name: String, schema: JSONSchema?, strict: Bool, description: String?)
      // {"type":"json_schema","name":"...","strict":true,"schema":...,"description":"..."}
      // `description` is omitted from JSON when nil
  }
  ```

- **TextParam**: Text response format and verbosity configuration.
  ```swift
  struct TextParam: Sendable, Encodable {
      let format: TextFormat?
      let verbosity: TextVerbosity?
      init(format: TextFormat? = nil, verbosity: TextVerbosity? = nil)
  }
  ```

- **StreamOptionsConfig**: Encoded body of `stream_options`.
  ```swift
  struct StreamOptionsConfig: Sendable, Encodable {
      let includeObfuscation: Bool  // JSON: "include_obfuscation"
  }
  ```

- **ResponseTextField**: Decoded `text` field on a response. Only the format `type` and `verbosity` are required by this package. Extra format keys are ignored.
  ```swift
  struct ResponseTextField: Sendable, Decodable {
      struct Format: Sendable, Decodable { let type: String }
      let format: Format?
      let verbosity: TextVerbosity?
  }
  ```

- **ResponseRequest**: The API request.
  ```swift
  struct ResponseRequest: Encodable, Sendable {
      let model: String
      let input: ResponseInput
      var instructions: String?
      var temperature: Double?
      var maxOutputTokens: Int?
      var topP: Double?
      var frequencyPenalty: Double?
      var presencePenalty: Double?
      var previousResponseId: String?
      var reasoning: ReasoningConfig?
      var truncation: Truncation?
      var serviceTier: ServiceTier?
      var metadata: [String: String]?
      var tools: [FunctionToolParam]?
      var toolChoice: ToolChoice?
      var parallelToolCalls: Bool?
      var include: [String]?
      var store: Bool?             // JSON: "store"
      var background: Bool?        // JSON: "background"
      var maxToolCalls: Int?       // JSON: "max_tool_calls"
      var text: TextParam?         // JSON: "text"
      var topLogprobs: Int?        // JSON: "top_logprobs"
      var safetyIdentifier: String? // JSON: "safety_identifier"
      var promptCacheKey: String?  // JSON: "prompt_cache_key"
      var streamOptions: StreamOptionsConfig? // JSON: "stream_options"
      let stream: Bool
      var requestTimeout: TimeInterval?   // Not encoded to JSON
      var resourceTimeout: TimeInterval?  // Not encoded to JSON

      // 1. Builder items + config
      init(model: String, stream: Bool = false,
           @ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] },
           @InputBuilder input: () -> [InputItem]) throws

      // 2. Array items + config
      init(model: String, stream: Bool = false,
           @ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] },
           input: [InputItem]) throws

      // 3. Text input + config
      init(model: String, stream: Bool = false,
           @ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] },
           text: String) throws
  }
  ```
  - JSON: Encodes with snake_case keys via `CodingKeys`. `requestTimeout` and `resourceTimeout` are excluded.

- **ResponseObject**: The API response.
  ```swift
  struct ResponseObject: Sendable, Decodable {
      let id: String
      let object: String
      let createdAt: Int          // JSON: "created_at"
      let completedAt: Int?       // JSON: "completed_at"
      let model: String
      let output: [OutputItem]
      let status: ResponseStatus
      let usage: Usage?
      let error: ErrorInfo?
      let incompleteDetails: IncompleteDetails?  // JSON: "incomplete_details"
      let previousResponseId: String?
      let metadata: [String: String]?
      let instructions: String?
      let temperature: Double?
      let topP: Double?                    // JSON: "top_p"
      let presencePenalty: Double?         // JSON: "presence_penalty"
      let frequencyPenalty: Double?        // JSON: "frequency_penalty"
      let topLogprobs: Int?                // JSON: "top_logprobs"
      let text: ResponseTextField?         // JSON: "text" — format type plus verbosity
      let truncation: Truncation?
      let serviceTier: String?             // JSON: "service_tier"; free string so unknown tiers still decode
      let maxOutputTokens: Int?            // JSON: "max_output_tokens"
      let store: Bool?
      let background: Bool?
      let safetyIdentifier: String?        // JSON: "safety_identifier"
      let promptCacheKey: String?          // JSON: "prompt_cache_key"

      struct OutputTokensDetails: Sendable, Decodable {
          let reasoningTokens: Int   // JSON: "reasoning_tokens"
      }

      struct InputTokensDetails: Sendable, Decodable {
          let cachedTokens: Int      // JSON: "cached_tokens"
      }

      struct Usage: Sendable, Decodable {
          let inputTokens: Int                          // JSON: "input_tokens"
          let outputTokens: Int                         // JSON: "output_tokens"
          let totalTokens: Int                          // JSON: "total_tokens"
          let outputTokensDetails: OutputTokensDetails? // JSON: "output_tokens_details"
          let inputTokensDetails: InputTokensDetails?   // JSON: "input_tokens_details"
      }

      struct IncompleteDetails: Sendable, Decodable {
          let reason: String
      }

      struct ErrorInfo: Sendable, Decodable {
          let code: String
          let message: String
      }
  }
  ```
  - Convenience extensions:
    - `firstOutputText: String?` — first text content from output messages
    - `firstFunctionCalls: [FunctionCallItem]?` — all function calls from output
    - `requiresToolExecution: Bool` — true if output contains function calls
    - `totalTokens: Int` — total tokens from usage
    - `reasoningItems: [ReasoningItem]` — all reasoning items from the output, in order
    - `firstReasoningItem: ReasoningItem?` — the first reasoning item in the output, if any
    - `reasoningTokens: Int` — reasoning tokens used (0 if unavailable)

### 8. Streaming Types

- **StreamEvent**: Semantic streaming events.
  ```swift
  enum StreamEvent: Sendable {
      case responseCreated(ResponseObject)
      case responseInProgress(ResponseObject)
      case responseQueued(ResponseObject)        // SSE: "response.queued"
      case responseIncomplete(ResponseObject)    // SSE: "response.incomplete"
      case outputItemAdded(OutputItem, index: Int)
      case contentPartAdded(index: Int, contentIndex: Int)
      case contentPartDelta(delta: String, index: Int, contentIndex: Int)
      case contentPartDone(index: Int, contentIndex: Int)
      case outputItemDone(OutputItem, index: Int)
      case functionCallArgumentsDelta(delta: String, callId: String, index: Int)
      case functionCallArgumentsDone(arguments: String, callId: String, index: Int)
      case responseCompleted(ResponseObject)
      case reasoningSummaryPartAdded(part: ReasoningSummary, index: Int, summaryIndex: Int)
      case reasoningSummaryPartDone(part: ReasoningSummary, index: Int, summaryIndex: Int)
      case responseFailed(ResponseObject)
      case error(String)
      case outputTextDelta(delta: String, index: Int, contentIndex: Int, itemId: String, sequenceNumber: Int, logprobs: [LogProb]?)
      case outputTextDone(text: String, index: Int, contentIndex: Int, itemId: String, sequenceNumber: Int, logprobs: [LogProb]?)
      case refusalDelta(delta: String, index: Int, contentIndex: Int, itemId: String, sequenceNumber: Int)
      case refusalDone(refusal: String, index: Int, contentIndex: Int, itemId: String, sequenceNumber: Int)
      case outputTextAnnotationAdded(annotation: Annotation?, index: Int, contentIndex: Int, annotationIndex: Int, itemId: String, sequenceNumber: Int)
      case reasoningDelta(delta: String, index: Int, contentIndex: Int, itemId: String, sequenceNumber: Int)
      case reasoningDone(text: String, index: Int, contentIndex: Int, itemId: String, sequenceNumber: Int)
      case reasoningSummaryTextDelta(delta: String, index: Int, summaryIndex: Int, itemId: String, sequenceNumber: Int)
      case reasoningSummaryTextDone(text: String, index: Int, summaryIndex: Int, itemId: String, sequenceNumber: Int)
  }
  ```
  - Existing cases stay unchanged so current switches keep compiling.
  - `response.output_text.delta` yields `contentPartDelta` and, when `item_id` and `sequence_number` are present, also `outputTextDelta` (including optional `logprobs`).
  - `response.output_text.done` yields `outputTextDone`.
  - `response.refusal.delta` and `response.refusal.done` yield `refusalDelta` and `refusalDone`.
  - `response.output_text.annotation.added` yields `outputTextAnnotationAdded`. `annotation` may be null.
  - `response.reasoning.delta` and `response.reasoning.done` yield `reasoningDelta` and `reasoningDone`.
  - `response.reasoning_summary_text.delta` and `response.reasoning_summary_text.done` yield `reasoningSummaryTextDelta` and `reasoningSummaryTextDone`.
  - `error` decodes an `ErrorPayload` (`type`, `code`, `message`, `param`) and uses `message` as the `error` string. If the payload does not match, the raw JSON string is used.

### 9. Actor: LLMClient

```swift
actor LLMClient {
    init(baseURL: String, apiKey: String, customHeaders: [String: String] = [:],
         sessionConfiguration: URLSessionConfiguration = .default) throws
    func send(_ request: ResponseRequest) async throws -> ResponseObject
    nonisolated func stream(_ request: ResponseRequest) -> AsyncThrowingStream<StreamEvent, Error>
    func prewarm()
}
```
- `customHeaders`: Additional HTTP headers applied to every request after the default `Authorization: Bearer` header, so a custom `Authorization` value will override the default Bearer token (e.g., for proxy auth scenarios).
- `send`: Non-streaming POST request.
- `stream`: Returns `AsyncThrowingStream<StreamEvent, Error>` for SSE streaming. Parses `event:` + `data:` pairs.
- `prewarm`: Opens this client's `URLSession` to `baseURL` without generating. Open Responses has no prewarm operation, so this is not a package gap and it is not listed in [`Unimplemented.md`](Unimplemented.md). The call is `GET` with the same `Authorization` and `customHeaders` as `send`, no body, and `timeoutInterval` of 5 seconds. `await prewarm()` returns after that GET is started. It does not wait for the response. The GET runs off the actor, so `send` and `stream` are not blocked. Failures are ignored. The request uses the session from `init`, including `sessionConfiguration`.

## Usage Examples

Calls below use the current initializers. `text:` stays inside the parentheses. A trailing closure after `config:` is the input builder. Throwing configuration values use `try`.

1. **Non-Streaming** (text input):
   ```swift
   let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")
   await client.prewarm()
   let response = try await client.send(
       try ResponseRequest(model: "gpt-4o", config: {
           try Temperature(0.7)
           try MaxOutputTokens(150)
       }, text: "Explain Swift concurrency.")
   )
   print(response.firstOutputText ?? "No response")
   ```
   `prewarm` sends `GET` on this client's session and returns after the request starts. Open Responses has no prewarm operation.

2. **Structured Input**:
   ```swift
   let response = try await client.send(
       try ResponseRequest(model: "gpt-4o", config: {
           try Temperature(0.7)
           try Instructions("You are a coding assistant.")
       }) {
           System("You are a coding assistant.")
           User("Explain Swift concurrency.")
       }
   )
   ```

3. **Streaming**:
   ```swift
   let stream = client.stream(
       try ResponseRequest(model: "gpt-4o", stream: true, config: {
           try Temperature(0.8)
       }, text: "Write a poem.")
   )
   for try await event in stream {
       if case .contentPartDelta(let delta, _, _) = event {
           print(delta, terminator: "")
       }
   }
   ```
   `response.output_text.delta` also yields `outputTextDelta` when `item_id` and `sequence_number` are present.

4. **Conversation Continuity**:
   ```swift
   let response1 = try await client.send(
       try ResponseRequest(model: "gpt-4o", text: "What is Swift?")
   )
   let response2 = try await client.send(
       try ResponseRequest(model: "gpt-4o", config: {
           try PreviousResponseId(response1.id)
       }, text: "Tell me more about its type system.")
   )
   ```

5. **Token Usage**:
   ```swift
   let response = try await client.send(
       try ResponseRequest(model: "gpt-4o", text: "Explain optionals.")
   )
   if let usage = response.usage {
       print("Input tokens:  \(usage.inputTokens)")
       print("Output tokens: \(usage.outputTokens)")
       print("Total tokens:  \(usage.totalTokens)")
   }
   // Convenience property (returns 0 if usage is nil):
   print("Total: \(response.totalTokens)")
   ```

6. **File input**:
   ```swift
   let response = try await client.send(
       try ResponseRequest(model: "gpt-4o") {
           UserFile(filename: "notes.txt", fileData: "aGVsbG8=", fileURL: "https://example.com/notes.txt")
           User("Summarize this file.")
       }
   )
   ```
   Nil `filename`, `fileData`, and `fileURL` are omitted. An `input_file` part on an output message still fails decoding.

7. **Text inference**:
   ```swift
   let stream = client.stream(
       try ResponseRequest(model: "gpt-4o", stream: true, config: {
           try TopLogprobs(5)
           try SafetyIdentifier("user-42")
           try PromptCacheKey("cache-abc")
           StreamOptions(includeObfuscation: false)
       }) {
           Assistant("Draft answer", phase: .commentary, id: "msg_1")
           User("Revise the draft.")
       }
   )
   for try await event in stream {
       if case .contentPartDelta(let delta, _, _) = event {
           print(delta, terminator: "")
       }
   }
   ```
   Resend `phase` on a later turn that includes prior assistant text. `stream: true` is read with `client.stream`. A server may omit these optional fields.

---

## Required Tests

1. **ResponseRequest Initialization and Configuration**
2. **Invalid Parameter Validation** (boundary testing for all config params)
3. **Request Encoding** (snake_case keys, optional fields, ResponseInput variants)
4. **Response Decoding** (polymorphic OutputItem, Usage, error)
5. **Item Type Encoding/Decoding** (InputItem, OutputItem polymorphism), including **file input**: `UserFile` / `inputFile` encode `type: input_file` and only the `filename`, `file_data`, and `file_url` values that are set
6. **InputBuilder result builder**
7. **LLMClient Init Validation**, and **connection warm**: `prewarm` returns in under a second, uses the client's session, sends `GET` with the same auth headers as `send`, and does not block a later call on the actor
8. **ToolChoice Encoding** (Responses API format)
9. **Streaming Event Parsing** (event+data SSE pairs)
10. **Edge Cases** (empty input, missing model)
11. **Text inference** (Open Responses 2026-04-24): encode `top_logprobs`, `safety_identifier`, `prompt_cache_key`, `stream_options`, and JSON Schema `description`; encode `Assistant` with `phase` and `output_text`; decode output `logprobs`, assistant `phase`, and `status: queued`; decode the optional text-generation fields on `ResponseObject`; parse each new text stream event, including both yields for `response.output_text.delta` and the `error` payload fallback.
12. **Live server tests**: `Spec/LiveTesting.md`. `swift test` runs them against a local server. The default base URL is `http://127.0.0.1:1234` and the default model is `openai/gpt-oss-20b`. The suite is skipped only when that server does not answer. LM Studio is the example of a Responses server without full spec support: the suite allows omitted echoes, rewritten `frequency_penalty` and `service_tier`, HTTP 400 on `item_reference` and object `tool_choice`, an ignored JSON format, empty `logprobs`, and reasoning without reasoning deltas.

---

## Maintenance Tooling

Claude Code was used to create this project initially. The committer has moved maintenance and expansion to Grok Build. When a session needs a model, use the latest Grok model available. Do not treat Claude Code as the current toolchain.

`AGENTS.md` must state this so every Grok Build session follows it. The README badge row shows Grok Build only; the Claude Code history stays in prose.

## Agent Instruction Files

Only the following agent-instruction files belong in this repository:

- **`AGENTS.md`** — Project instructions loaded automatically into every Grok Build session, including the maintenance-tooling rule above. Do not also commit `CLAUDE.md`; Grok loads both when they are separate files.
- **`skills/`** — Published Agent Skills (`using-swift-open-responses-dsl`, `design-responses-app`). Edit these copies.
- **`.grok/skills/`** — Symlinks to `skills/` so Grok Build discovers the same skills while working in this repo.

Do **not** commit:
- Memory files or session state (e.g., `.claude/projects/` auto-memory)
- Personal permission overrides (e.g., `.claude/settings.local.json`)
- Files containing personally identifiable information (names, API keys, email addresses, user paths)
- Files that are only meaningful on a specific local machine (absolute paths, local config overrides)
