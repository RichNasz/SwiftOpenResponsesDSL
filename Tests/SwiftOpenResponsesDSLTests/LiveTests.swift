//
//  LiveTests.swift
//  SwiftOpenResponsesDSL
//
//  Live integration tests against a local LLM server.
//  Set OPENRESPONSES_BASE_URL and OPENRESPONSES_MODEL env vars to configure.
//  Coverage and defaults are specified in Spec/LiveTesting.md.
//

import Foundation
import Testing
@testable import SwiftOpenResponsesDSL

// MARK: - Configuration

enum LiveTestConfig {
	static let baseURL: String = {
		ProcessInfo.processInfo.environment["OPENRESPONSES_BASE_URL"] ?? "http://127.0.0.1:1234"
	}()

	static let model: String = {
		ProcessInfo.processInfo.environment["OPENRESPONSES_MODEL"] ?? "openai/gpt-oss-20b"
	}()

	static let endpointURL: String = {
		baseURL.hasSuffix("/") ? "\(baseURL)v1/responses" : "\(baseURL)/v1/responses"
	}()

	static let reasoningModel: String = {
		ProcessInfo.processInfo.environment["OPENRESPONSES_REASONING_MODEL"] ?? model
	}()

	static let isServerAvailable: Bool = {
		guard let url = URL(string: endpointURL) else { return false }
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = 2
		// Send a minimal invalid request just to see if the server responds
		request.httpBody = Data("{}".utf8)

		let semaphore = DispatchSemaphore(value: 0)
		nonisolated(unsafe) var reachable = false
		let task = URLSession.shared.dataTask(with: request) { _, response, _ in
			// Any HTTP response means the server is up (even 400/422)
			if let http = response as? HTTPURLResponse, http.statusCode > 0 {
				reachable = true
			}
			semaphore.signal()
		}
		task.resume()
		_ = semaphore.wait(timeout: .now() + 3)
		return reachable
	}()
}

// MARK: - Live Tests

@Suite(.serialized, .enabled(if: LiveTestConfig.isServerAvailable, "Requires local LLM server"))
struct LiveTests {
	let client: LLMClient

	init() throws {
		client = try LLMClient(baseURL: LiveTestConfig.endpointURL, apiKey: "not-needed")
	}

	@Test func basicTextSend() async throws {
		let request = try ResponseRequest(
			model: LiveTestConfig.model,
			config: {
				try RequestTimeout(240)
			},
			text: "Reply with exactly one word: hello"
		)

		let response = try await client.send(request)

		#expect(response.status == .completed)
		#expect(response.id.isEmpty == false)
		let text = response.firstOutputText
		#expect(text != nil)
		#expect(text!.isEmpty == false)
		#expect(response.usage != nil)
		#expect(response.usage!.totalTokens > 0)
	}

	@Test func structuredInput() async throws {
		let request = try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
		}) {
			System("You are a helpful assistant. Keep responses brief.")
			User("What is 2+2? Reply with just the number.")
		}

		let response = try await client.send(request)

		#expect(response.status == .completed)
		let text = response.firstOutputText
		#expect(text != nil)
		#expect(text!.contains("4"))
	}

	@Test func conversationContinuity() async throws {
		let first = try ResponseRequest(
			model: LiveTestConfig.model,
			config: {
				try RequestTimeout(240)
			},
			text: "My name is TestBot. Remember it. Reply with OK."
		)
		let firstResponse = try await client.send(first)
		#expect(firstResponse.status == .completed)
		#expect(firstResponse.id.isEmpty == false)

		let second = try ResponseRequest(
			model: LiveTestConfig.model,
			config: {
				try RequestTimeout(240)
				try PreviousResponseId(firstResponse.id)
			},
			text: "What is my name? Reply with just the name."
		)
		let secondResponse = try await client.send(second)

		#expect(secondResponse.status == .completed)
		let text = secondResponse.firstOutputText
		#expect(text != nil)
		#expect(text!.contains("TestBot"))
	}

	@Test func streaming() async throws {
		let request = try ResponseRequest(
			model: LiveTestConfig.model,
			stream: true,
			config: {
				try RequestTimeout(240)
			},
			text: "Say hello in one sentence."
		)

		var deltas: [String] = []
		var gotCompleted = false
		var gotOutputItemDone = false

		for try await event in client.stream(request) {
			switch event {
			case .contentPartDelta(let delta, _, _):
				deltas.append(delta)
			case .outputItemDone:
				gotOutputItemDone = true
			case .responseCompleted(let response):
				gotCompleted = true
				#expect(response.status == .completed)
			default:
				break
			}
		}

		#expect(deltas.isEmpty == false)
		// Some local servers don't send response.completed or it may fail to decode;
		// outputItemDone or a clean stream finish is sufficient.
		#expect(gotCompleted || gotOutputItemDone)
		let fullText = deltas.joined()
		#expect(fullText.isEmpty == false)
	}

	@Test func toolSessionStreamingBasic() async throws {
		let session = ToolSession(
			client: client,
			tools: [],
			maxIterations: 10,
			handlers: [:]
		)

		var gotIterationStarted = false
		var gotContentDelta = false
		var gotToolCallStarted = false
		var gotToolCallCompleted = false

		for try await event in session.stream(
			model: LiveTestConfig.model,
			input: [User("Say hello in one word.")],
			configParams: [try RequestTimeout(240)]
		) {
			switch event {
			case .iterationStarted(let n) where n == 1:
				gotIterationStarted = true
			case .llm(.contentPartDelta):
				gotContentDelta = true
			case .toolCallStarted:
				gotToolCallStarted = true
			case .toolCallCompleted:
				gotToolCallCompleted = true
			default:
				break
			}
		}

		#expect(gotIterationStarted)
		#expect(gotContentDelta)
		#expect(gotToolCallStarted == false)
		#expect(gotToolCallCompleted == false)
	}

	@Test func toolSessionStreamingWithTools() async throws {
		let timeTool = FunctionToolParam(
			name: "get_current_time",
			description: "Returns the current time",
			parameters: .object(properties: [:], required: [])
		)
		let timeHandler: ToolSession.ToolHandler = { _ in "12:00 PM" }

		let session = ToolSession(
			client: client,
			tools: [timeTool],
			maxIterations: 10,
			handlers: ["get_current_time": timeHandler]
		)

		var events: [ToolSessionEvent] = []

		for try await event in session.stream(
			model: LiveTestConfig.model,
			input: [User("What time is it right now? You MUST use the get_current_time tool.")],
			configParams: [try RequestTimeout(240)]
		) {
			events.append(event)
		}

		// First event must be iterationStarted(1)
		if case .iterationStarted(let n) = events.first {
			#expect(n == 1)
		} else {
			Issue.record("Expected first event to be iterationStarted(1)")
		}

		let toolStarted = events.contains {
			if case .toolCallStarted(_, let name, _) = $0 { return name == "get_current_time" }
			return false
		}
		#expect(toolStarted)

		let toolCompleted = events.contains {
			if case .toolCallCompleted(_, let name, let output, _) = $0 {
				return name == "get_current_time" && output == "12:00 PM"
			}
			return false
		}
		#expect(toolCompleted)

		let secondIteration = events.contains {
			if case .iterationStarted(let n) = $0 { return n == 2 }
			return false
		}
		#expect(secondIteration)
	}

	@Test func agentStreaming() async throws {
		let timeTool = FunctionToolParam(
			name: "get_current_time",
			description: "Returns the current time",
			parameters: .object(properties: [:], required: [])
		)
		let timeHandler: ToolSession.ToolHandler = { _ in "12:00 PM" }

		let agent = Agent(
			client: client,
			model: LiveTestConfig.model,
			tools: [timeTool],
			toolHandlers: ["get_current_time": timeHandler],
			config: [try RequestTimeout(240)]
		)

		var gotToolCallStarted = false
		var gotToolCallCompleted = false
		var gotContentDelta = false

		for try await event in await agent.stream("What time is it? Use the get_current_time tool.") {
			switch event {
			case .toolCallStarted:
				gotToolCallStarted = true
			case .toolCallCompleted:
				gotToolCallCompleted = true
			case .llm(.contentPartDelta):
				gotContentDelta = true
			default:
				break
			}
		}

		#expect(gotToolCallStarted)
		#expect(gotToolCallCompleted)
		#expect(gotContentDelta)

		// lastResponseId is set only when the server emits response.completed;
		// some local servers omit this event, so we don't assert non-nil here.
		_ = await agent.lastResponseId

		let transcript = await agent.transcript
		let hasToolCall = transcript.contains { if case .toolCall = $0 { return true }; return false }
		let hasToolResult = transcript.contains { if case .toolResult = $0 { return true }; return false }
		#expect(hasToolCall)
		#expect(hasToolResult)
	}

	@Test func toolSessionRunUsageAggregation() async throws {
		let timeTool = FunctionToolParam(
			name: "get_current_time",
			description: "Returns the current time",
			parameters: .object(properties: [:], required: [])
		)
		let timeHandler: ToolSession.ToolHandler = { _ in "12:00 PM" }

		let session = ToolSession(
			client: client,
			tools: [timeTool],
			maxIterations: 10,
			handlers: ["get_current_time": timeHandler]
		)

		let result = try await session.run(
			model: LiveTestConfig.model,
			input: [User("What time is it right now? You MUST use the get_current_time tool.")],
			configParams: [try RequestTimeout(240)]
		)

		#expect(result.iterationUsages.isEmpty == false)
		#expect(result.totalUsage != nil)
		#expect(result.totalUsage!.totalTokens > 0)
	}

	@Test func agentSendUsage() async throws {
		let timeTool = FunctionToolParam(
			name: "get_current_time",
			description: "Returns the current time",
			parameters: .object(properties: [:], required: [])
		)
		let timeHandler: ToolSession.ToolHandler = { _ in "12:00 PM" }

		let agent = Agent(
			client: client,
			model: LiveTestConfig.model,
			tools: [timeTool],
			toolHandlers: ["get_current_time": timeHandler],
			config: [try RequestTimeout(240)]
		)

		_ = try await agent.send("What time is it? Use the get_current_time tool.")

		let usage = await agent.lastUsage
		#expect(usage != nil)
		#expect(usage!.totalTokens > 0)
	}

	@Test func reasoningNonStreaming() async throws {
		let request = try ResponseRequest(
			model: LiveTestConfig.reasoningModel,
			config: {
				try RequestTimeout(240)
				Reasoning(effort: .low, summary: .concise)
			},
			text: "What is 1+1?"
		)

		let response = try await client.send(request)

		#expect(response.status == .completed)
		let hasReasoningItem = response.output.contains {
			if case .reasoning = $0 { return true }
			return false
		}
		#expect(hasReasoningItem)
		#expect((response.usage?.outputTokensDetails?.reasoningTokens ?? 0) > 0)
	}

	@Test func reasoningStreaming() async throws {
		let request = try ResponseRequest(
			model: LiveTestConfig.reasoningModel,
			stream: true,
			config: {
				try RequestTimeout(240)
				Reasoning(effort: .low, summary: .concise)
			},
			text: "What is 1+1?"
		)

		var gotSummaryPartAdded = false
		var gotSummaryPartDone = false
		var gotReasoningEvent = false
		var completedResponse: ResponseObject?
		var gotAnyContent = false

		for try await event in client.stream(request) {
			switch event {
			case .reasoningSummaryPartAdded:
				gotSummaryPartAdded = true
				gotReasoningEvent = true
			case .reasoningSummaryPartDone:
				gotSummaryPartDone = true
				gotReasoningEvent = true
			case .reasoningDelta, .reasoningDone, .reasoningSummaryTextDelta, .reasoningSummaryTextDone:
				gotReasoningEvent = true
			case .contentPartDelta:
				gotAnyContent = true
			case .responseCompleted(let response):
				completedResponse = response
			default:
				break
			}
		}

		let completedHasReasoning = completedResponse?.output.contains { item in
			if case .reasoning = item { return true }
			return false
		} ?? false
		// Stream must produce some output
		#expect(gotAnyContent || completedResponse != nil)
		#expect(gotReasoningEvent || completedHasReasoning)

		// If the server emits summary events, both added and done must appear together
		if gotSummaryPartAdded || gotSummaryPartDone {
			#expect(gotSummaryPartAdded)
			#expect(gotSummaryPartDone)
		}

		// If the response was completed, verify reasoning item presence when summary events were emitted
		if let response = completedResponse {
			let hasReasoningItem = response.output.contains {
				if case .reasoning = $0 { return true }
				return false
			}
			if gotSummaryPartAdded {
				#expect(hasReasoningItem)
			}
		}
	}

	@Test func maxOutputTokens() async throws {
		let request = try ResponseRequest(
			model: LiveTestConfig.model,
			config: {
				try RequestTimeout(240)
				try MaxOutputTokens(50)
			},
			text: "Write a very long essay about the history of computing."
		)

		let response = try await client.send(request)

		#expect(response.usage != nil)
		#expect(response.usage!.outputTokens <= 60) // small margin for model variance
	}

	// MARK: - Full API coverage (Spec/LiveTesting.md)

	@Test func developerMessage() async throws {
		let request = try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
		}) {
			Developer("Reply with exactly the word ready.")
			User("Go.")
		}
		let response = try await client.send(request)
		#expect(response.status == .completed)
		#expect((response.firstOutputText ?? "").isEmpty == false)
	}

	@Test func assistantPhaseFollowUp() async throws {
		let first = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
		}, text: "Reply with exactly: blue"))
		let answer = first.firstOutputText ?? ""
		#expect(answer.isEmpty == false)
		let followUp = try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
		}) {
			Assistant(answer, phase: .finalAnswer, id: "msg_live")
			User("Repeat your last answer.")
		}
		let encoded = try JSONEncoder().encode(Assistant(answer, phase: .finalAnswer, id: "msg_live"))
		let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
		#expect(json?["phase"] as? String == "final_answer")
		let second = try await client.send(followUp)
		#expect(second.status == .completed)
	}

	@Test func itemReference() async throws {
		let first = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
		}, text: "Reply with exactly: cedar"))
		guard let itemId = firstOutputItemId(first) else {
			Issue.record("First response had no output item id")
			return
		}
		do {
			let second = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
				try RequestTimeout(240)
			}) {
				ItemReferenceInput(itemId)
				User("What word did you just say?")
			})
			#expect(second.status == .completed)
		} catch let error as LLMError {
			if case .serverError = error { return }
			throw error
		}
	}

	@Test func samplingParameters() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			try Temperature(0)
			try TopP(1)
			try FrequencyPenalty(0)
			try PresencePenalty(0)
		}, text: "Reply with exactly: ok"))
		#expect(response.temperature == 0)
		#expect(response.topP == 1)
		#expect(response.presencePenalty == 0)
		#expect(response.frequencyPenalty != nil)
	}

	@Test func instructions() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			try Instructions("Reply with the single word pong.")
		}, text: "ping"))
		#expect(response.instructions == "Reply with the single word pong.")
		#expect((response.firstOutputText ?? "").lowercased().contains("pong"))
	}

	@Test func requestOptions() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			TruncationParam(.auto)
			ServiceTierParam(.auto)
			Metadata(["suite": "live"])
			Store(false)
			Background(false)
		}, text: "Reply with exactly: ok"))
		#expect(response.truncation == .auto)
		#expect(response.serviceTier != nil)
		#expect(response.metadata?["suite"] == "live")
		#expect(response.store == false)
		#expect(response.background == false)
	}

	@Test func safetyAndCache() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			try SafetyIdentifier("live-user")
			try PromptCacheKey("live-cache")
		}, text: "Reply with exactly: ok"))
		if let safetyIdentifier = response.safetyIdentifier {
			#expect(safetyIdentifier == "live-user")
		}
		if let promptCacheKey = response.promptCacheKey {
			#expect(promptCacheKey == "live-cache")
		}
		#expect(response.status == .completed)
	}

	@Test func logprobs() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			try TopLogprobs(2)
			try IncludeParam(["message.output_text.logprobs"])
		}, text: "Reply with exactly: hi"))
		#expect(response.topLogprobs == 2)
		#expect(response.status == .completed)
	}

	@Test func jsonObjectFormat() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			TextConfig(TextParam(format: .jsonObject))
		}, text: "Return a JSON object {\"n\":1}"))
		#expect((response.firstOutputText ?? "").contains("{"))
	}

	@Test func jsonSchemaFormat() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			TextConfig(TextParam(format: .jsonSchema(
				name: "answer",
				schema: .object(properties: ["answer": .string()], required: ["answer"]),
				strict: true,
				description: "A one-word answer"
			)))
		}, text: "What is 1+1? Put the answer in the answer field."))
		#expect((response.firstOutputText ?? "").isEmpty == false)
	}

	@Test func streamOptions() async throws {
		let request = try ResponseRequest(model: LiveTestConfig.model, stream: true, config: {
			try RequestTimeout(240)
			StreamOptions(includeObfuscation: false)
		}, text: "Reply with exactly: hi")
		var sawDelta = false
		var sawOutputTextDelta = false
		var sawError = false
		for try await event in client.stream(request) {
			switch event {
			case .contentPartDelta:
				sawDelta = true
			case .outputTextDelta(_, _, _, let itemId, _, _):
				if itemId.isEmpty == false { sawOutputTextDelta = true }
			case .error:
				sawError = true
			default:
				break
			}
		}
		#expect(sawDelta)
		#expect(sawOutputTextDelta)
		#expect(sawError == false)
	}

	@Test func toolChoiceNone() async throws {
		let response = try await client.send(try toolRequest(
			choice: .none,
			prompt: "What time is it? Answer in one word without tools."
		))
		let calls = functionCalls(in: response)
		#expect(calls.isEmpty)
		#expect((response.firstOutputText ?? "").isEmpty == false)
	}

	@Test func toolChoiceFunction() async throws {
		do {
			let response = try await client.send(try toolRequest(
				choice: .function("get_current_time"),
				prompt: "What time is it?"
			))
			#expect(functionCalls(in: response).contains { $0.name == "get_current_time" })
		} catch let error as LLMError {
			if case .serverError = error { return }
			throw error
		}
	}

	@Test func toolChoiceRequired() async throws {
		let response = try await client.send(try toolRequest(
			choice: .required,
			prompt: "What time is it?"
		))
		#expect(functionCalls(in: response).isEmpty == false)
	}

	@Test func toolChoiceAllowed() async throws {
		do {
			let response = try await client.send(try toolRequest(
				choice: .allowedTools(mode: .auto, tools: ["get_current_time"]),
				prompt: "What time is it right now? You MUST use the get_current_time tool."
			))
			#expect(functionCalls(in: response).contains { $0.name == "get_current_time" })
		} catch let error as LLMError {
			if case .serverError = error { return }
			throw error
		}
	}

	@Test func parallelToolCallsOff() async throws {
		var request = try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			ParallelToolCalls(false)
			ToolChoiceParam(.auto)
		}, input: [User("Say ok.")])
		request.tools = [timeTool(), secondTool()]
		let response = try await client.send(request)
		#expect(response.id.isEmpty == false)
	}

	@Test func maxToolCallsOne() async throws {
		var request = try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			try MaxToolCalls(1)
			ToolChoiceParam(.required)
		}, input: [User("Call both get_current_time and get_weekday.")])
		request.tools = [timeTool(), secondTool()]
		let response = try await client.send(request)
		#expect(functionCalls(in: response).count <= 1)
	}

	@Test func resourceTimeout() async throws {
		let response = try await client.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(30)
			try ResourceTimeout(240)
		}, text: "Reply with exactly: ok"))
		#expect((response.firstOutputText ?? "").isEmpty == false)
	}

	@Test func customHeader() async throws {
		let headerClient = try LLMClient(
			baseURL: LiveTestConfig.endpointURL,
			apiKey: "not-needed",
			customHeaders: ["X-Live-Test": "1"]
		)
		let response = try await headerClient.send(try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
		}, text: "Reply with exactly: ok"))
		#expect((response.firstOutputText ?? "").isEmpty == false)
	}

	@Test func imageInput() async throws {
		let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
		let request = try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
		}) {
			UserImage(png, detail: "low")
			User("What color is this image? Reply with one word.")
		}
		do {
			let response = try await client.send(request)
			#expect(response.id.isEmpty == false)
		} catch let error as LLMError {
			if case .serverError = error {
				return
			}
			throw error
		}
	}

	private func timeTool() -> FunctionToolParam {
		FunctionToolParam(
			name: "get_current_time",
			description: "Returns the current time",
			parameters: .object(properties: [:], required: [])
		)
	}

	private func secondTool() -> FunctionToolParam {
		FunctionToolParam(
			name: "get_weekday",
			description: "Returns the current weekday",
			parameters: .object(properties: [:], required: [])
		)
	}

	private func toolRequest(choice: ToolChoice, prompt: String) throws -> ResponseRequest {
		var request = try ResponseRequest(model: LiveTestConfig.model, config: {
			try RequestTimeout(240)
			ToolChoiceParam(choice)
		}, input: [User(prompt)])
		request.tools = [timeTool()]
		return request
	}

	private func firstOutputItemId(_ response: ResponseObject) -> String? {
		switch response.output.first {
		case .message(let message):
			return message.id
		case .functionCall(let call), .functionCallOutput(let call):
			return call.id
		case .reasoning(let item):
			return item.id
		case nil:
			return nil
		}
	}

	private func functionCalls(in response: ResponseObject) -> [FunctionCallItem] {
		response.output.compactMap { item in
			if case .functionCall(let call) = item { return call }
			return nil
		}
	}
}

/// Wraps an output item id as an input item. Named to avoid clashing with the `ItemReference` value type.
private func ItemReferenceInput(_ id: String) -> InputItem {
	.itemReference(ItemReference(id: id))
}
