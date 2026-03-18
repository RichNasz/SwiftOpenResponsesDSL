# Specification for SwiftOpenResponsesDSL

## Overview
The **SwiftOpenResponsesDSL** is an embedded Swift DSL that simplifies communication with LLM inference servers supporting the [Open Responses API](https://www.openresponses.org/) specification. It abstracts HTTP requests, JSON serialization, authentication, and error handling into a declarative, type-safe interface, supporting both non-streaming and streaming responses. Users must provide the complete endpoint URL (`baseURL`) when initializing the client and the `model` in every request, ensuring compatibility with varied servers (e.g., `https://api.openai.com/v1/responses`, `https://your-server.com/v1/responses`). Optional parameters are specified via a `@ResponseConfigBuilder` block, allowing users to include only desired parameters with minimal code.

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
- **Swift Version**: 6.2+ (enable for trailing commas, `nonisolated`, improved type inference).
- **Dependencies**: SwiftLLMToolMacros (for JSONSchema and tool macros).
- **API Compatibility**: Align with Open Responses API JSON format for requests and responses (camelCase internally, snake_case in JSON via `CodingKeys`).
- **Testing**: Support Swift Testing for async validation (e.g., `#expect` with concurrency traits).
- **URL Handling**: Treat `baseURL` as the complete endpoint URL provided by the user, without modification.
- **Minimum OS Versions**: macOS 13.0, iOS 16.0.

---

## Core Components

### 1. Enums

- **Role**: Defines message roles for the Responses API.
  - Signature: `enum Role: String, Codable, Sendable { case system, user, assistant, developer }`
  - Purpose: Represents message roles. The Responses API uses `developer` instead of Chat Completions' `tool` role.
  - JSON: Encodes as strings (e.g., `"system"`).

- **ResponseStatus**: Status of a response.
  - Signature: `enum ResponseStatus: String, Codable, Sendable { case inProgress = "in_progress", completed, failed, incomplete }`

- **ReasoningEffort**: Controls reasoning depth.
  - Signature: `enum ReasoningEffort: String, Codable, Sendable { case none, low, medium, high, xhigh }`

- **ServiceTier**: Service tier selection.
  - Signature: `enum ServiceTier: String, Codable, Sendable { case auto, \`default\`, flex, priority }`

- **Truncation**: Truncation strategy.
  - Signature: `enum Truncation: String, Codable, Sendable { case auto, disabled }`

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
      case functionCallOutput(FunctionCallOutputItem)
      case itemReference(ItemReference)
  }
  ```
  - JSON: Encodes based on the inner type's `type` field.

- **InputMessage**: A message input item.
  ```swift
  struct InputMessage: Sendable, Encodable {
      let role: Role  // system, user, developer
      let content: InputContent
      // type is always "message"
  }
  ```

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
      case inputImage(url: String, detail: String?)
  }
  ```

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
  }
  ```

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

- **FunctionCallItem**: A function call in the output.
  ```swift
  struct FunctionCallItem: Sendable, Decodable {
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
      let encryptedContent: String?
  }
  ```

- **ReasoningSummary**: A summary entry in reasoning.
  ```swift
  struct ReasoningSummary: Sendable, Decodable {
      let type: String
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
- **Reasoning**: `init(effort: ReasoningEffort, summary: Truncation? = nil)` — sets `request.reasoning`
- **TruncationParam**: `init(_ value: Truncation)` — sets `request.truncation`
- **ServiceTierParam**: `init(_ value: ServiceTier)` — sets `request.serviceTier`
- **Metadata**: `init(_ value: [String: String])` — sets `request.metadata`
- **ParallelToolCalls**: `init(_ value: Bool)` — sets `request.parallelToolCalls`
- **RequestTimeout**: `init(_ value: TimeInterval) throws` — validates 10...900, sets `request.requestTimeout`
- **ResourceTimeout**: `init(_ value: TimeInterval) throws` — validates 30...3600, sets `request.resourceTimeout`

### 5. Convenience Message Functions

- `System(_ content: String) -> InputItem` — creates `.message(InputMessage(role: .system, content: .text(content)))`
- `Developer(_ content: String) -> InputItem` — creates `.message(InputMessage(role: .developer, content: .text(content)))`
- `User(_ content: String) -> InputItem` — creates `.message(InputMessage(role: .user, content: .text(content)))`
- `UserImage(_ url: String, detail: String? = nil) -> InputItem` — creates `.message(InputMessage(role: .user, content: .parts([.inputImage(url: url, detail: detail)])))`
- `FunctionOutput(callId: String, output: String) -> InputItem` — creates `.functionCallOutput(FunctionCallOutputItem(callId: callId, output: output))`

### 6. Result Builders

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
      let summary: Truncation?
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
      let createdAt: Int
      let model: String
      let output: [OutputItem]
      let status: ResponseStatus
      let usage: Usage?
      let error: ErrorInfo?
      let previousResponseId: String?
      let metadata: [String: String]?

      struct Usage: Sendable, Decodable {
          let inputTokens: Int
          let outputTokens: Int
          let totalTokens: Int
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

### 8. Streaming Types

- **StreamEvent**: Semantic streaming events.
  ```swift
  enum StreamEvent: Sendable {
      case responseCreated(ResponseObject)
      case responseInProgress(ResponseObject)
      case outputItemAdded(OutputItem, index: Int)
      case contentPartAdded(index: Int, contentIndex: Int)
      case contentPartDelta(delta: String, index: Int, contentIndex: Int)
      case contentPartDone(index: Int, contentIndex: Int)
      case outputItemDone(OutputItem, index: Int)
      case responseCompleted(ResponseObject)
      case responseFailed(ResponseObject)
      case error(String)
  }
  ```

### 9. Actor: LLMClient

```swift
actor LLMClient {
    init(baseURL: String, apiKey: String, sessionConfiguration: URLSessionConfiguration = .default) throws
    func send(_ request: ResponseRequest) async throws -> ResponseObject
    nonisolated func stream(_ request: ResponseRequest) -> AsyncThrowingStream<StreamEvent, Error>
}
```
- `send`: Non-streaming POST request.
- `stream`: Returns `AsyncThrowingStream<StreamEvent, Error>` for SSE streaming. Parses `event:` + `data:` pairs.

## Usage Examples

1. **Non-Streaming** (text input):
   ```swift
   let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")
   let response = try await client.send(
       try ResponseRequest(model: "gpt-4o") {
           try Temperature(0.7)
           try MaxOutputTokens(150)
       } text: "Explain Swift concurrency."
   )
   print(response.firstOutputText ?? "No response")
   ```

2. **Structured Input**:
   ```swift
   let response = try await client.send(
       try ResponseRequest(model: "gpt-4o") {
           try Temperature(0.7)
           Instructions("You are a coding assistant.")
       } input: {
           System("You are a coding assistant.")
           User("Explain Swift concurrency.")
       }
   )
   ```

3. **Streaming**:
   ```swift
   let stream = client.stream(
       try ResponseRequest(model: "gpt-4o", stream: true) {
           try Temperature(0.8)
       } text: "Write a poem."
   )
   for try await event in stream {
       if case .contentPartDelta(let delta, _, _) = event {
           print(delta, terminator: "")
       }
   }
   ```

4. **Conversation Continuity**:
   ```swift
   let response1 = try await client.send(
       try ResponseRequest(model: "gpt-4o") text: "What is Swift?"
   )
   let response2 = try await client.send(
       try ResponseRequest(model: "gpt-4o") {
           PreviousResponseId(response1.id)
       } text: "Tell me more about its type system."
   )
   ```

---

## Required Tests

1. **ResponseRequest Initialization and Configuration**
2. **Invalid Parameter Validation** (boundary testing for all config params)
3. **Request Encoding** (snake_case keys, optional fields, ResponseInput variants)
4. **Response Decoding** (polymorphic OutputItem, Usage, error)
5. **Item Type Encoding/Decoding** (InputItem, OutputItem polymorphism)
6. **InputBuilder result builder**
7. **LLMClient Init Validation**
8. **ToolChoice Encoding** (Responses API format)
9. **Streaming Event Parsing** (event+data SSE pairs)
10. **Edge Cases** (empty input, missing model)
