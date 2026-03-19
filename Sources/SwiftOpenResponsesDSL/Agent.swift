//
//  Agent.swift
//  SwiftOpenResponsesDSL
//
//  Created by Richard Naszcyniec on 3/18/26.
//  Code assisted by AI
//

import Foundation
import SwiftLLMToolMacros

// MARK: - Agent

/// Structured log entry for Agent debugging and observability.
public enum TranscriptEntry: Sendable {
	case userMessage(String)
	case assistantMessage(String)
	case toolCall(name: String, arguments: String)
	case toolResult(name: String, result: String, duration: Duration)
	case error(String)
}

/// Pairs a FunctionToolParam definition with its handler closure.
public struct AgentTool: Sendable {
	public let tool: FunctionToolParam
	public let handler: ToolSession.ToolHandler

	/// Creates an AgentTool with a tool definition and its handler closure.
	public init(tool: FunctionToolParam, handler: @escaping ToolSession.ToolHandler) {
		self.tool = tool
		self.handler = handler
	}

	/// Creates an AgentTool from a `LLMTool` instance.
	public init<T: LLMTool>(_ instance: T, strict: Bool? = nil) {
		let definition = T.toolDefinition
		self.init(tool: FunctionToolParam(from: definition, strict: strict)) { argumentsJSON in
			guard let data = argumentsJSON.data(using: .utf8) else {
				throw LLMError.decodingFailed("Failed to convert arguments to data")
			}
			let args = try JSONDecoder().decode(T.Arguments.self, from: data)
			let output = try await instance.call(arguments: args)
			return output.content
		}
	}
}

/// Result builder for declaratively registering tools with an Agent.
@resultBuilder
public struct AgentToolBuilder {
	public static func buildBlock(_ components: AgentTool...) -> [AgentTool] {
		Array(components)
	}

	public static func buildEither(first: [AgentTool]) -> [AgentTool] {
		first
	}

	public static func buildEither(second: [AgentTool]) -> [AgentTool] {
		second
	}

	public static func buildOptional(_ component: [AgentTool]?) -> [AgentTool] {
		component ?? []
	}

	public static func buildArray(_ components: [[AgentTool]]) -> [AgentTool] {
		components.flatMap { $0 }
	}
}

/// High-level persistent agent using `lastResponseId` for conversation continuity.
///
/// Unlike the Chat Completions Agent which maintains full message history,
/// this agent uses the Responses API's `previous_response_id` to chain conversations.
public actor Agent {
	private let client: LLMClient
	private let model: String
	private let instructions: String?
	private let tools: [FunctionToolParam]
	private let toolChoice: ToolChoice?
	private let toolHandlers: [String: ToolSession.ToolHandler]
	private let configParams: [ResponseConfigParameter]
	private let maxToolIterations: Int
	private var _lastResponseId: String?
	private var _transcript: [TranscriptEntry] = []

	/// The ID of the last response, used for conversation continuity.
	public var lastResponseId: String? {
		_lastResponseId
	}

	/// The debugging transcript of all agent activity.
	public var transcript: [TranscriptEntry] {
		_transcript
	}

	/// The names of all registered tools.
	public var registeredToolNames: [String] {
		tools.map(\.name)
	}

	/// The number of registered tools.
	public var toolCount: Int {
		tools.count
	}

	/// Creates a new Agent with explicit tool definitions and handlers.
	public init(
		client: LLMClient,
		model: String,
		instructions: String? = nil,
		tools: [FunctionToolParam] = [],
		toolChoice: ToolChoice? = nil,
		toolHandlers: [String: ToolSession.ToolHandler] = [:],
		config: [ResponseConfigParameter] = [],
		maxToolIterations: Int = 10
	) {
		let names = tools.map(\.name)
		let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys
		precondition(duplicates.isEmpty, "Duplicate tool names detected: \(duplicates.sorted().joined(separator: ", "))")

		self.client = client
		self.model = model
		self.instructions = instructions
		self.tools = tools
		self.toolChoice = toolChoice
		self.toolHandlers = toolHandlers
		self.configParams = config
		self.maxToolIterations = maxToolIterations
	}

	/// Creates a new Agent using the builder pattern for tools.
	public init(
		client: LLMClient,
		model: String,
		instructions: String? = nil,
		maxToolIterations: Int = 10,
		@ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] },
		@AgentToolBuilder tools: () -> [AgentTool]
	) throws {
		let agentTools = tools()
		let toolDefs = agentTools.map(\.tool)
		var handlers: [String: ToolSession.ToolHandler] = [:]
		for agentTool in agentTools {
			let name = agentTool.tool.name
			if handlers[name] != nil {
				throw LLMError.invalidValue("Duplicate tool name: '\(name)'")
			}
			handlers[name] = agentTool.handler
		}

		self.client = client
		self.model = model
		self.instructions = instructions
		self.tools = toolDefs
		self.toolChoice = nil
		self.toolHandlers = handlers
		self.configParams = try config()
		self.maxToolIterations = maxToolIterations
	}

	/// Creates a new Agent with declarative `@SessionBuilder` configuration.
	public init(
		client: LLMClient,
		model: String,
		maxToolIterations: Int = 10,
		@SessionBuilder configure: () -> [SessionComponent]
	) throws {
		let components = configure()
		var foundInstructions: String?
		var toolDefs: [FunctionToolParam] = []
		var handlers: [String: ToolSession.ToolHandler] = [:]

		for component in components {
			switch component {
			case .inputItem(let item):
				// Extract instructions from system messages
				if case .message(let msg) = item, msg.role == .system {
					if case .text(let text) = msg.content {
						foundInstructions = text
					}
				}
			case .agentTool(let agentTool):
				let name = agentTool.tool.name
				if handlers[name] != nil {
					throw LLMError.invalidValue("Duplicate tool name: '\(name)'")
				}
				toolDefs.append(agentTool.tool)
				handlers[name] = agentTool.handler
			}
		}

		self.client = client
		self.model = model
		self.instructions = foundInstructions
		self.tools = toolDefs
		self.toolChoice = nil
		self.toolHandlers = handlers
		self.configParams = []
		self.maxToolIterations = maxToolIterations
	}

	/// Sends a user message and returns the assistant's response.
	public func send(_ message: String) async throws -> String {
		_transcript.append(.userMessage(message))

		let input: [InputItem] = [User(message)]

		if tools.isEmpty {
			// No tools — simple completion
			var request = try ResponseRequest(model: model, input: input)
			if let instructions {
				request.instructions = instructions
			}
			if let lastId = _lastResponseId {
				request.previousResponseId = lastId
			}
			for param in configParams {
				param.apply(to: &request)
			}

			let response = try await client.send(request)
			let content = response.firstOutputText ?? ""
			_lastResponseId = response.id
			_transcript.append(.assistantMessage(content))
			return content
		}

		// Use ToolSession for tool-calling loop
		let session = ToolSession(
			client: client,
			tools: tools,
			toolChoice: toolChoice,
			maxIterations: maxToolIterations,
			handlers: toolHandlers
		)

		// Build config params including instructions and previous_response_id
		var allConfigParams: [ResponseConfigParameter] = configParams
		if let instructions {
			allConfigParams.append(try Instructions(instructions))
		}
		if let lastId = _lastResponseId {
			allConfigParams.append(try PreviousResponseId(lastId))
		}

		let result = try await session.run(
			model: model,
			input: input,
			configParams: allConfigParams
		)

		// Record tool activity
		for entry in result.log {
			_transcript.append(.toolCall(name: entry.name, arguments: entry.arguments))
			_transcript.append(.toolResult(name: entry.name, result: entry.result, duration: entry.duration))
		}

		let content = result.response.firstOutputText ?? ""
		_lastResponseId = result.response.id
		_transcript.append(.assistantMessage(content))
		return content
	}

	/// Sends a user message and returns the assistant's response (alias for `send`).
	public func run(_ message: String) async throws -> String {
		try await send(message)
	}

	/// Streams a user message, emitting real-time LLM and tool execution events.
	public func stream(_ message: String) -> AsyncThrowingStream<ToolSessionEvent, Error> {
		// Capture actor state synchronously before leaving the actor executor
		_transcript.append(.userMessage(message))
		let capturedModel = model
		let capturedTools = tools
		let capturedToolChoice = toolChoice
		let capturedToolHandlers = toolHandlers
		let capturedConfigParams = configParams
		let capturedInstructions = instructions
		let capturedLastResponseId = _lastResponseId
		let capturedMaxToolIterations = maxToolIterations
		let capturedClient = client
		let input: [InputItem] = [User(message)]

		return AsyncThrowingStream { continuation in
			let task = Task {
				do {
					if capturedTools.isEmpty {
						// No tools — stream simple completion
						var request = try ResponseRequest(model: capturedModel, stream: true, input: input)
						if let instructions = capturedInstructions {
							request.instructions = instructions
						}
						if let lastId = capturedLastResponseId {
							request.previousResponseId = lastId
						}
						for param in capturedConfigParams {
							param.apply(to: &request)
						}

						var textAccumulator = ""
						for try await event in capturedClient.stream(request) {
							continuation.yield(.llm(event))
							switch event {
							case .contentPartDelta(let delta, _, _):
								textAccumulator += delta
							case .responseCompleted(let response):
								self.updateLastResponseId(response.id)
							default:
								break
							}
						}
						self.appendTranscriptEntry(.assistantMessage(textAccumulator))
						continuation.finish()
					} else {
						// Use ToolSession for tool-calling loop
						let session = ToolSession(
							client: capturedClient,
							tools: capturedTools,
							toolChoice: capturedToolChoice,
							maxIterations: capturedMaxToolIterations,
							handlers: capturedToolHandlers
						)

						var allConfigParams: [ResponseConfigParameter] = capturedConfigParams
						if let instructions = capturedInstructions {
							allConfigParams.append(try Instructions(instructions))
						}
						if let lastId = capturedLastResponseId {
							allConfigParams.append(try PreviousResponseId(lastId))
						}

						var textAccumulator = ""
						for try await event in session.stream(model: capturedModel, input: input, configParams: allConfigParams) {
							continuation.yield(event)
							switch event {
							case .llm(.contentPartDelta(let delta, _, _)):
								textAccumulator += delta
							case .llm(.responseCompleted(let response)):
								self.updateLastResponseId(response.id)
							case .toolCallStarted(_, let name, let arguments):
								self.appendTranscriptEntry(.toolCall(name: name, arguments: arguments))
							case .toolCallCompleted(_, let name, let output, let duration):
								self.appendTranscriptEntry(.toolResult(name: name, result: output, duration: duration))
							default:
								break
							}
						}
						self.appendTranscriptEntry(.assistantMessage(textAccumulator))
						continuation.finish()
					}
				} catch {
					self.appendTranscriptEntry(.error(error.localizedDescription))
					continuation.finish(throwing: error)
				}
			}

			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}

	private func updateLastResponseId(_ id: String) {
		_lastResponseId = id
	}

	private func appendTranscriptEntry(_ entry: TranscriptEntry) {
		_transcript.append(entry)
	}

	/// Resets the agent's conversation state and transcript.
	public func reset() {
		_lastResponseId = nil
		_transcript.removeAll()
	}
}
