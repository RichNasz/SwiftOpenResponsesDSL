//
//  SwiftOpenResponsesDSL.swift
//  SwiftOpenResponsesDSL
//
//  Created by Richard Naszcyniec on 3/18/26.
//  Code assisted by AI
//

import Foundation
import SwiftLLMToolMacros

// MARK: - Core Enums

/// Defines message roles for the Open Responses API.
public enum Role: String, Codable, Sendable {
	/// Instructions that define the AI's behavior and personality
	case system
	/// Messages from the human user
	case user
	/// Responses from the AI assistant
	case assistant
	/// Developer-level instructions
	case developer
}

/// Status of a response.
public enum ResponseStatus: String, Codable, Sendable {
	case inProgress = "in_progress"
	case completed
	case failed
	case incomplete
}

/// Controls the depth of model reasoning.
public enum ReasoningEffort: String, Codable, Sendable {
	case none, low, medium, high
	case xhigh
}

/// Service tier selection for the request.
public enum ServiceTier: String, Codable, Sendable {
	case auto
	case `default`
	case flex
	case priority
}

/// Truncation strategy for conversation history.
public enum Truncation: String, Codable, Sendable {
	case auto
	case disabled
}

/// Comprehensive error types for LLM API operations.
public enum LLMError: Error, Equatable {
	case invalidURL
	case encodingFailed(String)
	case networkError(String)
	case decodingFailed(String)
	case serverError(statusCode: Int, message: String?)
	case rateLimit
	case invalidResponse
	case invalidValue(String)
	case missingBaseURL
	case missingModel
	case maxIterationsExceeded(Int)
	case unknownTool(String)
	case toolExecutionFailed(toolName: String, message: String)
}

// MARK: - Validation Helpers

/// Validates that a `Double` value falls within the specified range.
@inlinable
func validateRange(_ value: Double, in range: ClosedRange<Double>, parameterName: String) throws {
	guard range.contains(value) else {
		throw LLMError.invalidValue("\(parameterName) must be between \(range.lowerBound) and \(range.upperBound), got \(value)")
	}
}

/// Validates that a `TimeInterval` value falls within the specified range.
@inlinable
func validateTimeoutRange(_ value: TimeInterval, in range: ClosedRange<TimeInterval>, parameterName: String) throws {
	guard range.contains(value) else {
		throw LLMError.invalidValue("\(parameterName) must be between \(Int(range.lowerBound)) and \(Int(range.upperBound)) seconds, got \(value)")
	}
}

/// Validates that an `Int` value is greater than zero.
@inlinable
func validatePositive(_ value: Int, parameterName: String) throws {
	guard value > 0 else {
		throw LLMError.invalidValue("\(parameterName) must be greater than 0, got \(value)")
	}
}

/// Validates that a `String` value is not empty.
@inlinable
func validateNotEmpty(_ value: String, parameterName: String) throws {
	guard !value.isEmpty else {
		throw LLMError.invalidValue("\(parameterName) cannot be empty")
	}
}

// MARK: - Protocols

/// Protocol for configuration parameters that can modify a ``ResponseRequest``.
public protocol ResponseConfigParameter: Sendable {
	func apply(to request: inout ResponseRequest)
}

// MARK: - Input Item Types

/// Content of an input message — either plain text or structured parts.
public enum InputContent: Sendable {
	case text(String)
	case parts([InputContentPart])
}

extension InputContent: Encodable {
	public func encode(to encoder: Encoder) throws {
		switch self {
		case .text(let string):
			var container = encoder.singleValueContainer()
			try container.encode(string)
		case .parts(let parts):
			var container = encoder.unkeyedContainer()
			for part in parts {
				try container.encode(part)
			}
		}
	}
}

/// Individual content part within a structured message.
public enum InputContentPart: Sendable, Encodable {
	case inputText(String)
	case inputImage(url: String, detail: String?)

	private enum CodingKeys: String, CodingKey {
		case type, text, image_url, detail
	}

	private enum ImageURLKeys: String, CodingKey {
		case url, detail
	}

	public func encode(to encoder: Encoder) throws {
		switch self {
		case .inputText(let text):
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode("input_text", forKey: .type)
			try container.encode(text, forKey: .text)
		case .inputImage(let url, let detail):
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode("input_image", forKey: .type)
			var imageContainer = container.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .image_url)
			try imageContainer.encode(url, forKey: .url)
			if let detail {
				try imageContainer.encode(detail, forKey: .detail)
			}
		}
	}
}

/// A message input item with a role and content.
public struct InputMessage: Sendable, Encodable {
	public let role: Role
	public let content: InputContent

	private enum CodingKeys: String, CodingKey {
		case type, role, content
	}

	/// Creates a new InputMessage with the given role and content.
	public init(role: Role, content: InputContent) {
		self.role = role
		self.content = content
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode("message", forKey: .type)
		try container.encode(role, forKey: .role)
		try container.encode(content, forKey: .content)
	}
}

/// Result of a function call, sent back as input.
public struct FunctionCallOutputItem: Sendable, Encodable {
	public let callId: String
	public let output: String

	private enum CodingKeys: String, CodingKey {
		case type
		case callId = "call_id"
		case output
	}

	/// Creates a new FunctionCallOutputItem with the given call ID and output string.
	public init(callId: String, output: String) {
		self.callId = callId
		self.output = output
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode("function_call_output", forKey: .type)
		try container.encode(callId, forKey: .callId)
		try container.encode(output, forKey: .output)
	}
}

/// Reference to a previous output item by ID.
public struct ItemReference: Sendable, Encodable {
	public let id: String

	private enum CodingKeys: String, CodingKey {
		case type, id
	}

	/// Creates a new ItemReference with the given output item ID.
	public init(id: String) {
		self.id = id
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode("item_reference", forKey: .type)
		try container.encode(id, forKey: .id)
	}
}

/// Polymorphic input item for the Responses API.
public enum InputItem: Sendable, Encodable {
	case message(InputMessage)
	case functionCallOutput(FunctionCallOutputItem)
	case itemReference(ItemReference)

	public func encode(to encoder: Encoder) throws {
		switch self {
		case .message(let msg):
			try msg.encode(to: encoder)
		case .functionCallOutput(let item):
			try item.encode(to: encoder)
		case .itemReference(let ref):
			try ref.encode(to: encoder)
		}
	}
}

// MARK: - Output Item Types

/// Text annotation in output content.
public struct Annotation: Sendable {
	public let type: String
	public let startIndex: Int?
	public let endIndex: Int?
	public let url: String?
	public let title: String?

	/// Creates a new Annotation.
	public init(type: String, startIndex: Int? = nil, endIndex: Int? = nil, url: String? = nil, title: String? = nil) {
		self.type = type
		self.startIndex = startIndex
		self.endIndex = endIndex
		self.url = url
		self.title = title
	}
}

extension Annotation: Decodable {
	private enum CodingKeys: String, CodingKey {
		case type
		case startIndex = "start_index"
		case endIndex = "end_index"
		case url, title
	}
}

/// Text content with optional annotations.
public struct OutputTextContent: Sendable, Decodable {
	public let text: String
	public let annotations: [Annotation]?

	/// Creates a new OutputTextContent with text and optional annotations.
	public init(text: String, annotations: [Annotation]? = nil) {
		self.text = text
		self.annotations = annotations
	}
}

/// Content within an output message.
public enum OutputContent: Sendable {
	case outputText(OutputTextContent)
	case refusal(String)
}

extension OutputContent: Decodable {
	private enum CodingKeys: String, CodingKey {
		case type, text, refusal, annotations
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		switch type {
		case "output_text":
			let text = try container.decode(String.self, forKey: .text)
			let annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations)
			self = .outputText(OutputTextContent(text: text, annotations: annotations))
		case "refusal":
			let refusalText = try container.decode(String.self, forKey: .refusal)
			self = .refusal(refusalText)
		default:
			throw DecodingError.dataCorrupted(
				DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown output content type: \(type)")
			)
		}
	}
}

/// A message in the response output.
public struct OutputMessage: Sendable, Decodable {
	public let id: String
	public let role: Role
	public let content: [OutputContent]
	public let status: String?

	/// Creates a new OutputMessage.
	public init(id: String, role: Role, content: [OutputContent], status: String? = nil) {
		self.id = id
		self.role = role
		self.content = content
		self.status = status
	}
}

/// A function call in the response output.
public struct FunctionCallItem: Sendable, Decodable {
	public let id: String
	public let callId: String
	public let name: String
	public let arguments: String
	public let status: String?

	private enum CodingKeys: String, CodingKey {
		case id
		case callId = "call_id"
		case name, arguments, status
	}

	/// Creates a new FunctionCallItem.
	public init(id: String, callId: String, name: String, arguments: String, status: String? = nil) {
		self.id = id
		self.callId = callId
		self.name = name
		self.arguments = arguments
		self.status = status
	}

	/// Decodes the raw JSON arguments into a typed Swift value.
	public func decodeArguments<T: Decodable>(_ type: T.Type = T.self) throws -> T {
		guard let data = arguments.data(using: .utf8) else {
			throw LLMError.decodingFailed("Function call arguments are not valid UTF-8")
		}
		do {
			return try JSONDecoder().decode(T.self, from: data)
		} catch {
			throw LLMError.decodingFailed("Failed to decode function call arguments: \(error.localizedDescription)")
		}
	}
}

/// A summary entry within reasoning output.
public struct ReasoningSummary: Sendable, Decodable {
	public let type: String
	public let text: String

	/// Creates a new ReasoningSummary.
	public init(type: String, text: String) {
		self.type = type
		self.text = text
	}
}

/// Reasoning output item.
public struct ReasoningItem: Sendable, Decodable {
	public let id: String
	public let summary: [ReasoningSummary]?
	public let encryptedContent: String?

	private enum CodingKeys: String, CodingKey {
		case id, summary
		case encryptedContent = "encrypted_content"
	}

	/// Creates a new ReasoningItem.
	public init(id: String, summary: [ReasoningSummary]? = nil, encryptedContent: String? = nil) {
		self.id = id
		self.summary = summary
		self.encryptedContent = encryptedContent
	}
}

/// Polymorphic output item from the Responses API.
public enum OutputItem: Sendable {
	case message(OutputMessage)
	case functionCall(FunctionCallItem)
	case reasoning(ReasoningItem)
}

extension OutputItem: Decodable {
	private enum CodingKeys: String, CodingKey {
		case type
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		switch type {
		case "message":
			self = .message(try OutputMessage(from: decoder))
		case "function_call":
			self = .functionCall(try FunctionCallItem(from: decoder))
		case "reasoning":
			self = .reasoning(try ReasoningItem(from: decoder))
		default:
			throw DecodingError.dataCorrupted(
				DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown output item type: \(type)")
			)
		}
	}
}

// MARK: - Convenience Message Functions

/// Creates a system message input item.
@inlinable
public func System(_ content: String) -> InputItem {
	.message(InputMessage(role: .system, content: .text(content)))
}

/// Creates a developer message input item.
@inlinable
public func Developer(_ content: String) -> InputItem {
	.message(InputMessage(role: .developer, content: .text(content)))
}

/// Creates a user message input item.
@inlinable
public func User(_ content: String) -> InputItem {
	.message(InputMessage(role: .user, content: .text(content)))
}

/// Creates a user image input item.
@inlinable
public func UserImage(_ url: String, detail: String? = nil) -> InputItem {
	.message(InputMessage(role: .user, content: .parts([.inputImage(url: url, detail: detail)])))
}

/// Creates a function call output input item.
@inlinable
public func FunctionOutput(callId: String, output: String) -> InputItem {
	.functionCallOutput(FunctionCallOutputItem(callId: callId, output: output))
}

// MARK: - Configuration Parameter Structs

/// Controls the randomness and creativity of the AI's responses (0.0-2.0).
public struct Temperature: ResponseConfigParameter {
	public let value: Double

	/// Creates a temperature parameter. Validates range 0.0–2.0.
	/// - Throws: `LLMError.invalidValue` if out of range.
	public init(_ value: Double) throws {
		try validateRange(value, in: 0.0...2.0, parameterName: "Temperature")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.temperature = value
	}
}

/// Controls nucleus sampling (0.0-1.0).
public struct TopP: ResponseConfigParameter {
	public let value: Double

	/// Creates a top-p parameter. Validates range 0.0–1.0.
	/// - Throws: `LLMError.invalidValue` if out of range.
	public init(_ value: Double) throws {
		try validateRange(value, in: 0.0...1.0, parameterName: "TopP")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.topP = value
	}
}

/// Reduces repetition by penalizing frequent tokens (-2.0 to 2.0).
public struct FrequencyPenalty: ResponseConfigParameter {
	public let value: Double

	/// Creates a frequency penalty parameter. Validates range -2.0–2.0.
	/// - Throws: `LLMError.invalidValue` if out of range.
	public init(_ value: Double) throws {
		try validateRange(value, in: -2.0...2.0, parameterName: "FrequencyPenalty")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.frequencyPenalty = value
	}
}

/// Encourages new topics by penalizing already-appeared tokens (-2.0 to 2.0).
public struct PresencePenalty: ResponseConfigParameter {
	public let value: Double

	/// Creates a presence penalty parameter. Validates range -2.0–2.0.
	/// - Throws: `LLMError.invalidValue` if out of range.
	public init(_ value: Double) throws {
		try validateRange(value, in: -2.0...2.0, parameterName: "PresencePenalty")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.presencePenalty = value
	}
}

/// Limits the maximum number of output tokens (must be > 0).
public struct MaxOutputTokens: ResponseConfigParameter {
	public let value: Int

	/// Creates a max output tokens parameter. Validates value > 0.
	/// - Throws: `LLMError.invalidValue` if not positive.
	public init(_ value: Int) throws {
		try validatePositive(value, parameterName: "MaxOutputTokens")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.maxOutputTokens = value
	}
}

/// Sets system-level instructions for the model.
public struct Instructions: ResponseConfigParameter {
	public let value: String

	/// Creates an instructions parameter. Validates non-empty.
	/// - Throws: `LLMError.invalidValue` if empty.
	public init(_ value: String) throws {
		try validateNotEmpty(value, parameterName: "Instructions")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.instructions = value
	}
}

/// Sets the previous response ID for conversation continuity.
public struct PreviousResponseId: ResponseConfigParameter {
	public let value: String

	/// Creates a previous response ID parameter. Validates non-empty.
	/// - Throws: `LLMError.invalidValue` if empty.
	public init(_ value: String) throws {
		try validateNotEmpty(value, parameterName: "PreviousResponseId")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.previousResponseId = value
	}
}

/// Configures reasoning behavior (effort level and optional summary).
public struct Reasoning: ResponseConfigParameter {
	public let config: ReasoningConfig

	/// Creates a reasoning configuration with the given effort level and optional summary.
	public init(effort: ReasoningEffort, summary: Truncation? = nil) {
		self.config = ReasoningConfig(effort: effort, summary: summary)
	}

	public func apply(to request: inout ResponseRequest) {
		request.reasoning = config
	}
}

/// Sets the truncation strategy.
public struct TruncationParam: ResponseConfigParameter {
	public let value: Truncation

	/// Creates a truncation parameter with the given strategy.
	public init(_ value: Truncation) {
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.truncation = value
	}
}

/// Sets the service tier.
public struct ServiceTierParam: ResponseConfigParameter {
	public let value: ServiceTier

	/// Creates a service tier parameter with the given tier.
	public init(_ value: ServiceTier) {
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.serviceTier = value
	}
}

/// Sets request metadata.
public struct Metadata: ResponseConfigParameter {
	public let value: [String: String]

	/// Creates a metadata parameter with the given key-value pairs.
	public init(_ value: [String: String]) {
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.metadata = value
	}
}

/// Controls whether tool calls can be executed in parallel.
public struct ParallelToolCalls: ResponseConfigParameter {
	public let value: Bool

	/// Creates a parallel tool calls parameter.
	public init(_ value: Bool) {
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.parallelToolCalls = value
	}
}

/// Configures the timeout for individual HTTP requests (10-900 seconds).
public struct RequestTimeout: ResponseConfigParameter {
	public let value: TimeInterval

	/// Creates a request timeout parameter. Validates range 10–900 seconds.
	/// - Throws: `LLMError.invalidValue` if out of range.
	public init(_ value: TimeInterval) throws {
		try validateTimeoutRange(value, in: 10...900, parameterName: "Request timeout")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.requestTimeout = value
	}
}

/// Configures the timeout for complete resource loading (30-3600 seconds).
public struct ResourceTimeout: ResponseConfigParameter {
	public let value: TimeInterval

	/// Creates a resource timeout parameter. Validates range 30–3600 seconds.
	/// - Throws: `LLMError.invalidValue` if out of range.
	public init(_ value: TimeInterval) throws {
		try validateTimeoutRange(value, in: 30...3600, parameterName: "Resource timeout")
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.resourceTimeout = value
	}
}

// MARK: - JSON Schema

/// Type alias for the macros package JSON Schema type.
public typealias JSONSchema = JSONSchemaValue

extension JSONSchemaValue {
	/// Creates an object schema from a dictionary of properties.
	public static func object(
		properties: [String: JSONSchemaValue],
		required: [String] = []
	) -> JSONSchemaValue {
		.object(
			properties: properties.sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
			required: required
		)
	}
}

// MARK: - Tool Choice

/// Controls how the model selects tools during generation.
public enum ToolChoice: Sendable, Equatable, Encodable {
	case auto
	case none
	case required
	case function(String)

	public func encode(to encoder: Encoder) throws {
		switch self {
		case .auto:
			var container = encoder.singleValueContainer()
			try container.encode("auto")
		case .none:
			var container = encoder.singleValueContainer()
			try container.encode("none")
		case .required:
			var container = encoder.singleValueContainer()
			try container.encode("required")
		case .function(let name):
			// Responses API format: {"type":"function","name":"..."}
			var container = encoder.container(keyedBy: FunctionChoiceKeys.self)
			try container.encode("function", forKey: .type)
			try container.encode(name, forKey: .name)
		}
	}

	private enum FunctionChoiceKeys: String, CodingKey {
		case type, name
	}
}

/// Configuration parameter that sets the tool choice strategy.
public struct ToolChoiceParam: ResponseConfigParameter {
	public let value: ToolChoice

	public init(_ value: ToolChoice) {
		self.value = value
	}

	public func apply(to request: inout ResponseRequest) {
		request.toolChoice = value
	}
}

// MARK: - Tool Definition

/// A function tool definition for the Responses API.
public struct FunctionToolParam: Sendable, Encodable {
	public let type: String
	public let name: String
	public let description: String
	public let parameters: JSONSchema
	public let strict: Bool?

	private enum CodingKeys: String, CodingKey {
		case type, name, description, parameters, strict
	}

	/// Creates a new function tool definition with the given name, description, and JSON Schema parameters.
	public init(
		name: String,
		description: String,
		parameters: JSONSchema,
		strict: Bool? = nil
	) {
		self.type = "function"
		self.name = name
		self.description = description
		self.parameters = parameters
		self.strict = strict
	}

	/// Creates a FunctionToolParam from a macros ToolDefinition.
	public init(from definition: ToolDefinition, strict: Bool? = nil) {
		self.type = "function"
		self.name = definition.name
		self.description = definition.description
		self.parameters = definition.parameters
		self.strict = strict
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(type, forKey: .type)
		try container.encode(name, forKey: .name)
		try container.encode(description, forKey: .description)
		try container.encode(parameters, forKey: .parameters)
		if let strict {
			try container.encode(strict, forKey: .strict)
		}
	}
}

// MARK: - Result Builders

/// Result builder for composing input item sequences.
@resultBuilder
public struct InputBuilder {
	@inlinable
	public static func buildBlock(_ components: InputItem...) -> [InputItem] {
		Array(components)
	}

	@inlinable
	public static func buildEither(first: [InputItem]) -> [InputItem] {
		first
	}

	@inlinable
	public static func buildEither(second: [InputItem]) -> [InputItem] {
		second
	}

	@inlinable
	public static func buildOptional(_ component: [InputItem]?) -> [InputItem] {
		component ?? []
	}

	@inlinable
	public static func buildArray(_ components: [[InputItem]]) -> [InputItem] {
		components.flatMap { $0 }
	}

	@inlinable
	public static func buildLimitedAvailability(_ component: [InputItem]) -> [InputItem] {
		component
	}
}

/// Result builder for composing configuration parameters.
@resultBuilder
public struct ResponseConfigBuilder {
	@inlinable
	public static func buildBlock(_ components: ResponseConfigParameter...) -> [ResponseConfigParameter] {
		Array(components)
	}

	@inlinable
	public static func buildEither(first: [ResponseConfigParameter]) -> [ResponseConfigParameter] {
		first
	}

	@inlinable
	public static func buildEither(second: [ResponseConfigParameter]) -> [ResponseConfigParameter] {
		second
	}

	@inlinable
	public static func buildOptional(_ component: [ResponseConfigParameter]?) -> [ResponseConfigParameter] {
		component ?? []
	}

	@inlinable
	public static func buildArray(_ components: [[ResponseConfigParameter]]) -> [ResponseConfigParameter] {
		components.flatMap { $0 }
	}

	@inlinable
	public static func buildLimitedAvailability(_ component: [ResponseConfigParameter]) -> [ResponseConfigParameter] {
		component
	}
}

/// Result builder for composing ``FunctionToolParam`` arrays declaratively.
@resultBuilder
public struct ToolsBuilder {
	public static func buildBlock(_ components: FunctionToolParam...) -> [FunctionToolParam] {
		Array(components)
	}

	public static func buildEither(first: [FunctionToolParam]) -> [FunctionToolParam] {
		first
	}

	public static func buildEither(second: [FunctionToolParam]) -> [FunctionToolParam] {
		second
	}

	public static func buildOptional(_ component: [FunctionToolParam]?) -> [FunctionToolParam] {
		component ?? []
	}

	public static func buildArray(_ components: [[FunctionToolParam]]) -> [FunctionToolParam] {
		components.flatMap { $0 }
	}
}

// MARK: - Request / Response Types

/// Represents the `input` field of a Responses API request.
public enum ResponseInput: Sendable, Encodable {
	case text(String)
	case items([InputItem])

	public func encode(to encoder: Encoder) throws {
		switch self {
		case .text(let string):
			var container = encoder.singleValueContainer()
			try container.encode(string)
		case .items(let items):
			var container = encoder.unkeyedContainer()
			for item in items {
				try container.encode(item)
			}
		}
	}
}

/// Configuration for model reasoning.
public struct ReasoningConfig: Sendable, Encodable {
	public let effort: ReasoningEffort
	public let summary: Truncation?

	public init(effort: ReasoningEffort, summary: Truncation? = nil) {
		self.effort = effort
		self.summary = summary
	}
}

/// Represents a complete Responses API request.
public struct ResponseRequest: Encodable, Sendable {
	public let model: String
	public let input: ResponseInput
	public var instructions: String?
	public var temperature: Double?
	public var maxOutputTokens: Int?
	public var topP: Double?
	public var frequencyPenalty: Double?
	public var presencePenalty: Double?
	public var previousResponseId: String?
	public var reasoning: ReasoningConfig?
	public var truncation: Truncation?
	public var serviceTier: ServiceTier?
	public var metadata: [String: String]?
	public var tools: [FunctionToolParam]?
	public var toolChoice: ToolChoice?
	public var parallelToolCalls: Bool?
	public let stream: Bool
	public var requestTimeout: TimeInterval?
	public var resourceTimeout: TimeInterval?

	private enum CodingKeys: String, CodingKey {
		case model, input, instructions, temperature
		case maxOutputTokens = "max_output_tokens"
		case topP = "top_p"
		case frequencyPenalty = "frequency_penalty"
		case presencePenalty = "presence_penalty"
		case previousResponseId = "previous_response_id"
		case reasoning, truncation
		case serviceTier = "service_tier"
		case metadata, tools
		case toolChoice = "tool_choice"
		case parallelToolCalls = "parallel_tool_calls"
		case stream
	}

	/// Creates a request with builder-based input items and config.
	public init(
		model: String,
		stream: Bool = false,
		@ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] },
		@InputBuilder input: () -> [InputItem]
	) throws {
		guard !model.isEmpty else { throw LLMError.missingModel }
		self.model = model
		self.input = .items(input())
		self.stream = stream
		let params = try config()
		for param in params {
			param.apply(to: &self)
		}
	}

	/// Creates a request with an array of input items and config.
	public init(
		model: String,
		stream: Bool = false,
		@ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] },
		input: [InputItem]
	) throws {
		guard !model.isEmpty else { throw LLMError.missingModel }
		self.model = model
		self.input = .items(input)
		self.stream = stream
		let params = try config()
		for param in params {
			param.apply(to: &self)
		}
	}

	/// Creates a request with text input and config.
	public init(
		model: String,
		stream: Bool = false,
		@ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] },
		text: String
	) throws {
		guard !model.isEmpty else { throw LLMError.missingModel }
		self.model = model
		self.input = .text(text)
		self.stream = stream
		let params = try config()
		for param in params {
			param.apply(to: &self)
		}
	}
}

/// Represents a Responses API response object.
public struct ResponseObject: Sendable, Decodable {
	public let id: String
	public let object: String
	public let createdAt: Int
	public let model: String
	public let output: [OutputItem]
	public let status: ResponseStatus
	public let usage: Usage?
	public let error: ErrorInfo?
	public let previousResponseId: String?
	public let metadata: [String: String]?

	private enum CodingKeys: String, CodingKey {
		case id, object
		case createdAt = "created_at"
		case model, output, status, usage, error
		case previousResponseId = "previous_response_id"
		case metadata
	}

	/// Creates a new ResponseObject.
	public init(
		id: String,
		object: String = "response",
		createdAt: Int = 0,
		model: String,
		output: [OutputItem],
		status: ResponseStatus,
		usage: Usage? = nil,
		error: ErrorInfo? = nil,
		previousResponseId: String? = nil,
		metadata: [String: String]? = nil
	) {
		self.id = id
		self.object = object
		self.createdAt = createdAt
		self.model = model
		self.output = output
		self.status = status
		self.usage = usage
		self.error = error
		self.previousResponseId = previousResponseId
		self.metadata = metadata
	}

	/// Token usage information.
	public struct Usage: Sendable, Decodable {
		public let inputTokens: Int
		public let outputTokens: Int
		public let totalTokens: Int

		private enum CodingKeys: String, CodingKey {
			case inputTokens = "input_tokens"
			case outputTokens = "output_tokens"
			case totalTokens = "total_tokens"
		}

		/// Creates a new Usage with the given token counts.
		public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
			self.inputTokens = inputTokens
			self.outputTokens = outputTokens
			self.totalTokens = totalTokens
		}
	}

	/// Error information from the API.
	public struct ErrorInfo: Sendable, Decodable {
		public let code: String
		public let message: String

		/// Creates a new ErrorInfo with the given error code and message.
		public init(code: String, message: String) {
			self.code = code
			self.message = message
		}
	}
}

// MARK: - Response Convenience Extensions

extension ResponseObject {
	/// The first text content from output messages.
	public var firstOutputText: String? {
		for item in output {
			if case .message(let msg) = item {
				for content in msg.content {
					if case .outputText(let textContent) = content {
						return textContent.text
					}
				}
			}
		}
		return nil
	}

	/// All function calls from the output.
	public var firstFunctionCalls: [FunctionCallItem]? {
		let calls = output.compactMap { item -> FunctionCallItem? in
			if case .functionCall(let call) = item { return call }
			return nil
		}
		return calls.isEmpty ? nil : calls
	}

	/// Whether the response contains function calls that need execution.
	public var requiresToolExecution: Bool {
		firstFunctionCalls != nil
	}

	/// Total tokens used (0 if usage unavailable).
	public var totalTokens: Int {
		usage?.totalTokens ?? 0
	}
}

// MARK: - Streaming Types

/// Semantic streaming events from the Responses API.
public enum StreamEvent: Sendable {
	case responseCreated(ResponseObject)
	case responseInProgress(ResponseObject)
	case outputItemAdded(OutputItem, index: Int)
	case contentPartAdded(index: Int, contentIndex: Int)
	case contentPartDelta(delta: String, index: Int, contentIndex: Int)
	case contentPartDone(index: Int, contentIndex: Int)
	case outputItemDone(OutputItem, index: Int)
	case functionCallArgumentsDelta(delta: String, callId: String, index: Int)
	case functionCallArgumentsDone(arguments: String, callId: String, index: Int)
	case responseCompleted(ResponseObject)
	case responseFailed(ResponseObject)
	case error(String)
}

// MARK: - LLMClient

/// Thread-safe client for the Open Responses API.
public actor LLMClient {
	private let baseURL: URL
	private let apiKey: String
	private let session: URLSession

	/// Creates a new LLMClient.
	/// - Parameters:
	///   - baseURL: Complete endpoint URL (e.g., "https://api.openai.com/v1/responses")
	///   - apiKey: API key for authentication
	///   - sessionConfiguration: URLSession configuration (defaults to .default)
	/// - Throws: `LLMError.missingBaseURL` if URL is empty or invalid
	public init(baseURL: String, apiKey: String, sessionConfiguration: URLSessionConfiguration = .default) throws {
		guard !baseURL.isEmpty, let url = URL(string: baseURL) else {
			throw LLMError.missingBaseURL
		}
		self.baseURL = url
		self.apiKey = apiKey
		self.session = URLSession(configuration: sessionConfiguration)
	}

	/// Sends a non-streaming request and returns the response.
	public func send(_ request: ResponseRequest) async throws -> ResponseObject {
		var urlRequest = URLRequest(url: baseURL)
		urlRequest.httpMethod = "POST"
		urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
		urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

		if let timeout = request.requestTimeout {
			urlRequest.timeoutInterval = timeout
		}

		let encoder = JSONEncoder()
		do {
			urlRequest.httpBody = try encoder.encode(request)
		} catch {
			throw LLMError.encodingFailed(error.localizedDescription)
		}

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await session.data(for: urlRequest)
		} catch {
			throw LLMError.networkError(error.localizedDescription)
		}

		guard let httpResponse = response as? HTTPURLResponse else {
			throw LLMError.invalidResponse
		}

		if httpResponse.statusCode == 429 {
			throw LLMError.rateLimit
		}

		guard (200..<300).contains(httpResponse.statusCode) else {
			let message = String(data: data, encoding: .utf8)
			throw LLMError.serverError(statusCode: httpResponse.statusCode, message: message)
		}

		let decoder = JSONDecoder()
		do {
			return try decoder.decode(ResponseObject.self, from: data)
		} catch {
			throw LLMError.decodingFailed(error.localizedDescription)
		}
	}

	/// Streams a request and returns an async stream of semantic events.
	nonisolated public func stream(_ request: ResponseRequest) -> AsyncThrowingStream<StreamEvent, Error> {
		AsyncThrowingStream { continuation in
			let task = Task { [baseURL, apiKey, session] in
				var urlRequest = URLRequest(url: baseURL)
				urlRequest.httpMethod = "POST"
				urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
				urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

				if let timeout = request.requestTimeout {
					urlRequest.timeoutInterval = timeout
				}

				let encoder = JSONEncoder()
				do {
					urlRequest.httpBody = try encoder.encode(request)
				} catch {
					continuation.finish(throwing: LLMError.encodingFailed(error.localizedDescription))
					return
				}

				do {
					let (bytes, response) = try await session.bytes(for: urlRequest)

					guard let httpResponse = response as? HTTPURLResponse else {
						continuation.finish(throwing: LLMError.invalidResponse)
						return
					}

					if httpResponse.statusCode == 429 {
						continuation.finish(throwing: LLMError.rateLimit)
						return
					}

					guard (200..<300).contains(httpResponse.statusCode) else {
						continuation.finish(throwing: LLMError.serverError(statusCode: httpResponse.statusCode, message: nil))
						return
					}

					var currentEventType: String?
					let decoder = JSONDecoder()

					for try await line in bytes.lines {
						if line.hasPrefix("event: ") {
							currentEventType = String(line.dropFirst(7))
						} else if line.hasPrefix("data: ") {
							let jsonString = String(line.dropFirst(6))
							guard let eventType = currentEventType else { continue }
							guard let jsonData = jsonString.data(using: .utf8) else { continue }

							let event = Self.parseStreamEvent(eventType: eventType, data: jsonData, decoder: decoder)
							if let event {
								continuation.yield(event)
							}
							currentEventType = nil
						} else if line.isEmpty {
							currentEventType = nil
						}
					}

					continuation.finish()
				} catch {
					continuation.finish(throwing: LLMError.networkError(error.localizedDescription))
				}
			}

			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}

	private static func parseStreamEvent(eventType: String, data: Data, decoder: JSONDecoder) -> StreamEvent? {
		switch eventType {
		case "response.created":
			if let obj = try? decoder.decode(ResponseObject.self, from: data) {
				return .responseCreated(obj)
			}
		case "response.in_progress":
			if let obj = try? decoder.decode(ResponseObject.self, from: data) {
				return .responseInProgress(obj)
			}
		case "response.output_item.added":
			if let wrapper = try? decoder.decode(OutputItemEventWrapper.self, from: data) {
				return .outputItemAdded(wrapper.item, index: wrapper.outputIndex)
			}
		case "response.content_part.added":
			if let wrapper = try? decoder.decode(ContentPartEventWrapper.self, from: data) {
				return .contentPartAdded(index: wrapper.outputIndex, contentIndex: wrapper.contentIndex)
			}
		case "response.output_text.delta":
			if let wrapper = try? decoder.decode(TextDeltaEventWrapper.self, from: data) {
				return .contentPartDelta(delta: wrapper.delta, index: wrapper.outputIndex, contentIndex: wrapper.contentIndex)
			}
		case "response.content_part.done":
			if let wrapper = try? decoder.decode(ContentPartEventWrapper.self, from: data) {
				return .contentPartDone(index: wrapper.outputIndex, contentIndex: wrapper.contentIndex)
			}
		case "response.output_item.done":
			if let wrapper = try? decoder.decode(OutputItemEventWrapper.self, from: data) {
				return .outputItemDone(wrapper.item, index: wrapper.outputIndex)
			}
		case "response.function_call_arguments.delta":
			if let wrapper = try? decoder.decode(FunctionCallArgumentsEventWrapper.self, from: data),
			   let delta = wrapper.delta {
				return .functionCallArgumentsDelta(delta: delta, callId: wrapper.callId, index: wrapper.outputIndex)
			}
		case "response.function_call_arguments.done":
			if let wrapper = try? decoder.decode(FunctionCallArgumentsEventWrapper.self, from: data),
			   let arguments = wrapper.arguments {
				return .functionCallArgumentsDone(arguments: arguments, callId: wrapper.callId, index: wrapper.outputIndex)
			}
		case "response.completed":
			if let obj = try? decoder.decode(ResponseObject.self, from: data) {
				return .responseCompleted(obj)
			}
		case "response.failed":
			if let obj = try? decoder.decode(ResponseObject.self, from: data) {
				return .responseFailed(obj)
			}
		case "error":
			if let str = String(data: data, encoding: .utf8) {
				return .error(str)
			}
		default:
			break
		}
		return nil
	}
}

// MARK: - SSE Event Wrapper Types

struct OutputItemEventWrapper: Decodable {
	let item: OutputItem
	let outputIndex: Int

	private enum CodingKeys: String, CodingKey {
		case item
		case outputIndex = "output_index"
	}
}

struct ContentPartEventWrapper: Decodable {
	let outputIndex: Int
	let contentIndex: Int

	private enum CodingKeys: String, CodingKey {
		case outputIndex = "output_index"
		case contentIndex = "content_index"
	}
}

struct TextDeltaEventWrapper: Decodable {
	let delta: String
	let outputIndex: Int
	let contentIndex: Int

	private enum CodingKeys: String, CodingKey {
		case delta
		case outputIndex = "output_index"
		case contentIndex = "content_index"
	}
}

struct FunctionCallArgumentsEventWrapper: Decodable {
	let delta: String?
	let arguments: String?
	let callId: String
	let outputIndex: Int

	private enum CodingKeys: String, CodingKey {
		case delta, arguments
		case callId = "call_id"
		case outputIndex = "output_index"
	}
}
