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

// MARK: - Tool Session Event

/// Events emitted during a streaming ToolSession run.
public enum ToolSessionEvent: Sendable {
	/// Emitted before each LLM request (1-indexed).
	case iterationStarted(Int)
	/// A forwarded event from the LLM's SSE stream.
	case llm(StreamEvent)
	/// Emitted just before a tool handler is invoked.
	case toolCallStarted(callId: String, name: String, arguments: String)
	/// Emitted after a tool handler returns.
	case toolCallCompleted(callId: String, name: String, output: String, duration: Duration)
	/// Emitted after each LLM response completes, when usage data is present (1-indexed iteration).
	case usageUpdate(ResponseObject.Usage, iteration: Int)
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
	/// Token usage for each LLM call, in order (one entry per iteration).
	public let iterationUsages: [ResponseObject.Usage]

	/// Sum of all iteration usages, or nil if no response included usage data.
	public var totalUsage: ResponseObject.Usage? {
		guard !iterationUsages.isEmpty else { return nil }
		let input  = iterationUsages.reduce(0) { $0 + $1.inputTokens }
		let output = iterationUsages.reduce(0) { $0 + $1.outputTokens }
		let total  = iterationUsages.reduce(0) { $0 + $1.totalTokens }
		return ResponseObject.Usage(inputTokens: input, outputTokens: output, totalTokens: total)
	}
}

/// Orchestrates the tool-calling loop, accumulating full conversation history across iterations.
///
/// Each iteration appends function calls and their outputs to the input array, ensuring
/// the model sees what tools it already called and what results it received.
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
		var allUsages: [ResponseObject.Usage] = []
		var iterations = 0
		var currentInput = input

		// Build and send initial request
		var request = try ResponseRequest(model: model, input: currentInput)
		request.tools = tools
		request.toolChoice = toolChoice
		for param in configParams {
			param.apply(to: &request)
		}

		var response = try await client.send(request)
		if let u = response.usage { allUsages.append(u) }

		while iterations < maxIterations {
			guard response.requiresToolExecution,
				  let functionCalls = response.firstFunctionCalls, !functionCalls.isEmpty else {
				return ToolSessionResult(
					response: response,
					iterations: iterations,
					log: allLog,
					iterationUsages: allUsages
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

			// Accumulate function calls and their outputs into conversation history
			for call in functionCalls {
				currentInput.append(.functionCall(call))
			}
			for (index, result, logEntry) in results {
				allLog.append(logEntry)
				currentInput.append(
					.functionCallOutput(FunctionCallOutputItem(
						callId: functionCalls[index].callId,
						output: result
					))
				)
			}

			// Send next request with accumulated conversation history
			var nextRequest = try ResponseRequest(model: model, input: currentInput)
			nextRequest.tools = tools
			nextRequest.toolChoice = toolChoice
			for param in configParams {
				param.apply(to: &nextRequest)
			}

			response = try await client.send(nextRequest)
			if let u = response.usage { allUsages.append(u) }
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

	/// Streams the tool-calling loop, emitting real-time LLM and tool execution events.
	public func stream(
		model: String,
		input: [InputItem],
		configParams: [ResponseConfigParameter] = []
	) -> AsyncThrowingStream<ToolSessionEvent, Error> {
		AsyncThrowingStream { continuation in
			let task = Task {
				do {
					var currentInput = input
					var iteration = 0

					while true {
						continuation.yield(.iterationStarted(iteration + 1))

						// Build request
						var request = try ResponseRequest(model: model, stream: true, input: currentInput)
						request.tools = tools
						request.toolChoice = toolChoice
						for param in configParams {
							param.apply(to: &request)
						}

						// Stream the LLM response, collecting function calls
						var functionCalls: [FunctionCallItem] = []
						var completedUsage: ResponseObject.Usage? = nil

						for try await event in client.stream(request) {
							continuation.yield(.llm(event))
							switch event {
							case .outputItemDone(let item, _):
								if case .functionCall(let call) = item {
									functionCalls.append(call)
								}
							case .responseCompleted(let response):
								completedUsage = response.usage
							default:
								break
							}
						}

						if let usage = completedUsage {
							continuation.yield(.usageUpdate(usage, iteration: iteration + 1))
						}

						// No function calls — final response, done
						if functionCalls.isEmpty {
							continuation.finish()
							return
						}

						guard iteration < maxIterations else {
							throw LLMError.maxIterationsExceeded(maxIterations)
						}

						// Execute tool handlers in parallel, emitting events as they complete
						let results = try await withThrowingTaskGroup(
							of: (Int, String, String, Duration).self
						) { group in
							for (index, call) in functionCalls.enumerated() {
								guard let handler = handlers[call.name] else {
									throw LLMError.unknownTool(call.name)
								}
								let callId = call.callId
								let name = call.name
								let arguments = call.arguments
								continuation.yield(.toolCallStarted(callId: callId, name: name, arguments: arguments))
								group.addTask {
									let clock = ContinuousClock()
									let start = clock.now
									do {
										let result = try await handler(arguments)
										let duration = clock.now - start
										continuation.yield(.toolCallCompleted(callId: callId, name: name, output: result, duration: duration))
										return (index, callId, result, duration)
									} catch {
										throw LLMError.toolExecutionFailed(
											toolName: name,
											message: "[\(type(of: error))] \(error.localizedDescription)"
										)
									}
								}
							}

							var collected: [(Int, String, String, Duration)] = []
							for try await result in group {
								collected.append(result)
							}
							return collected.sorted { $0.0 < $1.0 }
						}

						// Accumulate function calls and their outputs into conversation history
						for call in functionCalls {
							currentInput.append(.functionCall(call))
						}
						for (_, callId, result, _) in results {
							currentInput.append(
								.functionCallOutput(FunctionCallOutputItem(
									callId: callId,
									output: result
								))
							)
						}
						iteration += 1
					}
				} catch {
					continuation.finish(throwing: error)
				}
			}

			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}

	/// Streams the tool-calling loop with a user prompt using the declarative configuration.
	public func stream(_ prompt: String) -> AsyncThrowingStream<ToolSessionEvent, Error> {
		guard let model else {
			preconditionFailure("stream(_:) requires ToolSession to be created with the declarative init(client:model:configure:) initializer")
		}
		let input = initialInput + [User(prompt)]
		return stream(model: model, input: input)
	}
}
