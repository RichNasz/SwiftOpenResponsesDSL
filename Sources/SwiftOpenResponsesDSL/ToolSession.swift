//
//  ToolSession.swift
//  SwiftOpenResponsesDSL
//
//  Created by Richard Naszcyniec on 3/18/26.
//  Code assisted by AI
//

import Foundation

// MARK: - Session Component

/// A component that can appear inside a `@SessionBuilder` block.
public enum SessionComponent: Sendable {
	case inputItem(InputItem)
	case agentTool(AgentTool)
}

// MARK: - Session Builder

/// Result builder for declaratively configuring a session with both input items and tools.
@resultBuilder
public struct SessionBuilder {
	public static func buildExpression(_ item: InputItem) -> [SessionComponent] {
		[.inputItem(item)]
	}

	public static func buildExpression(_ tool: AgentTool) -> [SessionComponent] {
		[.agentTool(tool)]
	}

	public static func buildBlock(_ components: [SessionComponent]...) -> [SessionComponent] {
		components.flatMap { $0 }
	}

	public static func buildEither(first: [SessionComponent]) -> [SessionComponent] {
		first
	}

	public static func buildEither(second: [SessionComponent]) -> [SessionComponent] {
		second
	}

	public static func buildOptional(_ component: [SessionComponent]?) -> [SessionComponent] {
		component ?? []
	}

	public static func buildArray(_ components: [[SessionComponent]]) -> [SessionComponent] {
		components.flatMap { $0 }
	}
}

// MARK: - Tool Session

/// Log entry for a single tool call execution within a ToolSession.
public struct ToolCallLogEntry: Sendable {
	public let name: String
	public let arguments: String
	public let result: String
	public let duration: Duration
}

/// Result of a ToolSession run.
public struct ToolSessionResult: Sendable {
	public let response: ResponseObject
	public let iterations: Int
	public let log: [ToolCallLogEntry]
}

/// Orchestrates the tool-calling loop using `previous_response_id` for conversation continuity.
///
/// Unlike the Chat Completions DSL which re-sends full message history, this implementation
/// uses the Responses API's `previous_response_id` to maintain context between iterations.
public struct ToolSession: Sendable {
	/// Closure type for tool handlers: takes raw JSON arguments, returns result string.
	public typealias ToolHandler = @Sendable (String) async throws -> String

	private let client: LLMClient
	private let tools: [FunctionToolParam]
	private let toolChoice: ToolChoice?
	private let handlers: [String: ToolHandler]
	private let maxIterations: Int
	private let model: String?
	private let initialInput: [InputItem]

	/// Creates a new ToolSession with explicit tool definitions.
	public init(
		client: LLMClient,
		tools: [FunctionToolParam],
		toolChoice: ToolChoice? = nil,
		maxIterations: Int = 10,
		handlers: [String: ToolHandler]
	) {
		let names = tools.map(\.name)
		let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys
		precondition(duplicates.isEmpty, "Duplicate tool names detected: \(duplicates.sorted().joined(separator: ", "))")

		self.client = client
		self.tools = tools
		self.toolChoice = toolChoice
		self.maxIterations = maxIterations
		self.handlers = handlers
		self.model = nil
		self.initialInput = []
	}

	/// Creates a new ToolSession with declarative configuration.
	public init(
		client: LLMClient,
		model: String,
		toolChoice: ToolChoice? = nil,
		maxIterations: Int = 10,
		@SessionBuilder configure: () -> [SessionComponent]
	) {
		let components = configure()
		var inputItems: [InputItem] = []
		var toolDefs: [FunctionToolParam] = []
		var toolHandlers: [String: ToolHandler] = [:]

		for component in components {
			switch component {
			case .inputItem(let item):
				inputItems.append(item)
			case .agentTool(let agentTool):
				toolDefs.append(agentTool.tool)
				toolHandlers[agentTool.tool.name] = agentTool.handler
			}
		}

		let names = toolDefs.map(\.name)
		let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys
		precondition(duplicates.isEmpty, "Duplicate tool names detected: \(duplicates.sorted().joined(separator: ", "))")

		self.client = client
		self.tools = toolDefs
		self.toolChoice = toolChoice
		self.maxIterations = maxIterations
		self.handlers = toolHandlers
		self.model = model
		self.initialInput = inputItems
	}

	/// Runs the tool-calling loop until the model produces a final response.
	public func run(
		model: String,
		input: [InputItem],
		@ResponseConfigBuilder config: () throws -> [ResponseConfigParameter] = { [] }
	) async throws -> ToolSessionResult {
		try await run(model: model, input: input, configParams: config())
	}

	/// Runs the tool-calling loop with pre-computed configuration parameters.
	public func run(
		model: String,
		input: [InputItem],
		configParams: [ResponseConfigParameter]
	) async throws -> ToolSessionResult {
		var allLog: [ToolCallLogEntry] = []
		var iterations = 0

		// Build and send initial request
		var request = try ResponseRequest(model: model, input: input)
		request.tools = tools
		request.toolChoice = toolChoice
		for param in configParams {
			param.apply(to: &request)
		}

		var response = try await client.send(request)

		while iterations < maxIterations {
			guard response.requiresToolExecution,
				  let functionCalls = response.firstFunctionCalls, !functionCalls.isEmpty else {
				return ToolSessionResult(
					response: response,
					iterations: iterations,
					log: allLog
				)
			}

			// Execute all function call handlers in parallel
			let results = try await withThrowingTaskGroup(
				of: (Int, String, ToolCallLogEntry).self
			) { group in
				for (index, call) in functionCalls.enumerated() {
					let handlerName = call.name
					guard let handler = handlers[handlerName] else {
						throw LLMError.unknownTool(handlerName)
					}

					group.addTask {
						let clock = ContinuousClock()
						let start = clock.now
						do {
							let result = try await handler(call.arguments)
							let duration = clock.now - start
							let logEntry = ToolCallLogEntry(
								name: handlerName,
								arguments: call.arguments,
								result: result,
								duration: duration
							)
							return (index, result, logEntry)
						} catch {
							throw LLMError.toolExecutionFailed(
								toolName: handlerName,
								message: "[\(type(of: error))] \(error.localizedDescription)"
							)
						}
					}
				}

				var collected: [(Int, String, ToolCallLogEntry)] = []
				for try await result in group {
					collected.append(result)
				}
				return collected.sorted { $0.0 < $1.0 }
			}

			// Build function call output items
			var outputItems: [InputItem] = []
			for (index, result, logEntry) in results {
				allLog.append(logEntry)
				outputItems.append(
					.functionCallOutput(FunctionCallOutputItem(
						callId: functionCalls[index].callId,
						output: result
					))
				)
			}

			// Send next request with previous_response_id
			var nextRequest = try ResponseRequest(model: model, input: outputItems)
			nextRequest.previousResponseId = response.id
			nextRequest.tools = tools
			nextRequest.toolChoice = toolChoice
			for param in configParams {
				param.apply(to: &nextRequest)
			}

			response = try await client.send(nextRequest)
			iterations += 1
		}

		throw LLMError.maxIterationsExceeded(maxIterations)
	}

	/// Runs the tool-calling loop with a user prompt using the declarative configuration.
	public func run(_ prompt: String) async throws -> ToolSessionResult {
		guard let model else {
			preconditionFailure("run(_:) requires ToolSession to be created with the declarative init(client:model:configure:) initializer")
		}
		let input = initialInput + [User(prompt)]
		return try await run(model: model, input: input)
	}
}
