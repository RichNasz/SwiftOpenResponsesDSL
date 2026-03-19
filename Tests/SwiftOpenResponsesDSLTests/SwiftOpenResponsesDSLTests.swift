//
//  SwiftOpenResponsesDSLTests.swift
//  SwiftOpenResponsesDSL
//
//  Created by Richard Naszcyniec on 3/18/26.
//  Code assisted by AI
//

import Foundation
import Testing
@testable import SwiftOpenResponsesDSL

// MARK: - ResponseRequest Initialization Tests

@Test func testResponseRequestWithTextInput() throws {
	let request = try ResponseRequest(model: "gpt-4o", config: {
		try Temperature(0.7)
		try MaxOutputTokens(150)
	}, text: "Hello, world!")

	#expect(request.model == "gpt-4o")
	#expect(request.temperature == 0.7)
	#expect(request.maxOutputTokens == 150)
	if case .text(let text) = request.input {
		#expect(text == "Hello, world!")
	} else {
		Issue.record("Expected text input")
	}
}

@Test func testResponseRequestWithBuilderInput() throws {
	let request = try ResponseRequest(model: "gpt-4o", config: {
		try Temperature(0.5)
	}) {
		System("You are helpful.")
		User("Hello!")
	}

	#expect(request.model == "gpt-4o")
	#expect(request.temperature == 0.5)
	if case .items(let items) = request.input {
		#expect(items.count == 2)
	} else {
		Issue.record("Expected items input")
	}
}

@Test func testResponseRequestWithArrayInput() throws {
	let items: [InputItem] = [
		System("Be helpful."),
		User("Hello"),
	]

	let request = try ResponseRequest(model: "gpt-4o", input: items)

	if case .items(let inputItems) = request.input {
		#expect(inputItems.count == 2)
	} else {
		Issue.record("Expected items input")
	}
}

@Test func testResponseRequestEmptyModel() {
	#expect(throws: LLMError.missingModel) {
		try ResponseRequest(model: "", text: "test")
	}
}

@Test func testResponseRequestStreamFlag() throws {
	let request = try ResponseRequest(model: "gpt-4o", stream: true, text: "Test")

	#expect(request.stream == true)
}

// MARK: - Parameter Validation Tests

@Test func testTemperatureValidation() throws {
	_ = try Temperature(0.0)
	_ = try Temperature(1.0)
	_ = try Temperature(2.0)

	#expect(throws: (any Error).self) {
		try Temperature(-0.1)
	}
	#expect(throws: (any Error).self) {
		try Temperature(2.1)
	}
}

@Test func testMaxOutputTokensValidation() throws {
	_ = try MaxOutputTokens(1)
	_ = try MaxOutputTokens(4096)

	#expect(throws: (any Error).self) {
		try MaxOutputTokens(0)
	}
	#expect(throws: (any Error).self) {
		try MaxOutputTokens(-10)
	}
}

@Test func testTopPValidation() throws {
	_ = try TopP(0.0)
	_ = try TopP(0.5)
	_ = try TopP(1.0)

	#expect(throws: (any Error).self) {
		try TopP(-0.1)
	}
	#expect(throws: (any Error).self) {
		try TopP(1.1)
	}
}

@Test func testFrequencyPenaltyValidation() throws {
	_ = try FrequencyPenalty(-2.0)
	_ = try FrequencyPenalty(0.0)
	_ = try FrequencyPenalty(2.0)

	#expect(throws: (any Error).self) {
		try FrequencyPenalty(-2.1)
	}
	#expect(throws: (any Error).self) {
		try FrequencyPenalty(2.1)
	}
}

@Test func testPresencePenaltyValidation() throws {
	_ = try PresencePenalty(-2.0)
	_ = try PresencePenalty(0.0)
	_ = try PresencePenalty(2.0)

	#expect(throws: (any Error).self) {
		try PresencePenalty(-2.1)
	}
	#expect(throws: (any Error).self) {
		try PresencePenalty(2.1)
	}
}

@Test func testInstructionsValidation() throws {
	_ = try Instructions("Be helpful")

	#expect(throws: (any Error).self) {
		try Instructions("")
	}
}

@Test func testPreviousResponseIdValidation() throws {
	_ = try PreviousResponseId("resp_123")

	#expect(throws: (any Error).self) {
		try PreviousResponseId("")
	}
}

@Test func testRequestTimeoutValidation() throws {
	_ = try RequestTimeout(10)
	_ = try RequestTimeout(900)

	#expect(throws: (any Error).self) {
		try RequestTimeout(9)
	}
	#expect(throws: (any Error).self) {
		try RequestTimeout(901)
	}
}

@Test func testResourceTimeoutValidation() throws {
	_ = try ResourceTimeout(30)
	_ = try ResourceTimeout(3600)

	#expect(throws: (any Error).self) {
		try ResourceTimeout(29)
	}
	#expect(throws: (any Error).self) {
		try ResourceTimeout(3601)
	}
}

// MARK: - LLMClient Tests

@Test func testLLMClientInitValidation() throws {
	_ = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-test")

	#expect(throws: LLMError.missingBaseURL) {
		try LLMClient(baseURL: "", apiKey: "sk-test")
	}
}

@Test func testLLMClientCustomSessionConfiguration() throws {
	let config = URLSessionConfiguration.default
	config.timeoutIntervalForRequest = 30.0

	_ = try LLMClient(
		baseURL: "https://api.openai.com/v1/responses",
		apiKey: "sk-test",
		sessionConfiguration: config
	)
}

// MARK: - JSON Encoding Tests

@Test func testResponseRequestEncoding() throws {
	let request = try ResponseRequest(model: "gpt-4o", config: {
		try Temperature(0.7)
		try MaxOutputTokens(100)
		try TopP(0.9)
	}, text: "Hello")

	let encoder = JSONEncoder()
	let data = try encoder.encode(request)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["model"] as? String == "gpt-4o")
	#expect(json?["temperature"] as? Double == 0.7)
	#expect(json?["max_output_tokens"] as? Int == 100)
	#expect(json?["top_p"] as? Double == 0.9)
	#expect(json?["input"] as? String == "Hello")
	#expect(json?["stream"] as? Bool == false)
	// requestTimeout and resourceTimeout should NOT be in JSON
	#expect(json?["requestTimeout"] == nil)
	#expect(json?["resourceTimeout"] == nil)
}

@Test func testResponseRequestEncodingWithItems() throws {
	let request = try ResponseRequest(model: "gpt-4o") {
		System("Be helpful.")
		User("Hello!")
	}

	let encoder = JSONEncoder()
	let data = try encoder.encode(request)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["model"] as? String == "gpt-4o")
	let input = json?["input"] as? [[String: Any]]
	#expect(input?.count == 2)
	#expect(input?[0]["type"] as? String == "message")
	#expect(input?[0]["role"] as? String == "system")
	#expect(input?[1]["type"] as? String == "message")
	#expect(input?[1]["role"] as? String == "user")
}

@Test func testFunctionCallOutputEncoding() throws {
	let item = FunctionCallOutputItem(callId: "call_123", output: "{\"temp\": 72}")

	let encoder = JSONEncoder()
	let data = try encoder.encode(item)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["type"] as? String == "function_call_output")
	#expect(json?["call_id"] as? String == "call_123")
	#expect(json?["output"] as? String == "{\"temp\": 72}")
}

@Test func testInputMessageEncoding() throws {
	let msg = InputMessage(role: .developer, content: .text("Follow rules."))

	let encoder = JSONEncoder()
	let data = try encoder.encode(msg)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["type"] as? String == "message")
	#expect(json?["role"] as? String == "developer")
	#expect(json?["content"] as? String == "Follow rules.")
}

@Test func testItemReferenceEncoding() throws {
	let ref = ItemReference(id: "item_abc")

	let encoder = JSONEncoder()
	let data = try encoder.encode(ref)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["type"] as? String == "item_reference")
	#expect(json?["id"] as? String == "item_abc")
}

// MARK: - JSON Decoding Tests

@Test func testResponseObjectDecoding() throws {
	let jsonString = """
	{
		"id": "resp_123",
		"object": "response",
		"created_at": 1700000000,
		"model": "gpt-4o",
		"output": [
			{
				"type": "message",
				"id": "msg_1",
				"role": "assistant",
				"content": [
					{
						"type": "output_text",
						"text": "Hello! How can I help?"
					}
				],
				"status": "completed"
			}
		],
		"status": "completed",
		"usage": {
			"input_tokens": 10,
			"output_tokens": 8,
			"total_tokens": 18
		}
	}
	"""

	let data = jsonString.data(using: .utf8)!
	let decoder = JSONDecoder()
	let response = try decoder.decode(ResponseObject.self, from: data)

	#expect(response.id == "resp_123")
	#expect(response.object == "response")
	#expect(response.createdAt == 1700000000)
	#expect(response.model == "gpt-4o")
	#expect(response.status == .completed)
	#expect(response.output.count == 1)
	#expect(response.usage?.inputTokens == 10)
	#expect(response.usage?.outputTokens == 8)
	#expect(response.usage?.totalTokens == 18)
	#expect(response.firstOutputText == "Hello! How can I help?")
	#expect(response.totalTokens == 18)
}

@Test func testOutputItemFunctionCallDecoding() throws {
	let jsonString = """
	{
		"type": "function_call",
		"id": "fc_1",
		"call_id": "call_abc",
		"name": "get_weather",
		"arguments": "{\\"location\\": \\"Paris\\"}",
		"status": "completed"
	}
	"""

	let data = jsonString.data(using: .utf8)!
	let decoder = JSONDecoder()
	let item = try decoder.decode(OutputItem.self, from: data)

	if case .functionCall(let call) = item {
		#expect(call.id == "fc_1")
		#expect(call.callId == "call_abc")
		#expect(call.name == "get_weather")
		#expect(call.status == "completed")
	} else {
		Issue.record("Expected function call output item")
	}
}

@Test func testOutputItemReasoningDecoding() throws {
	let jsonString = """
	{
		"type": "reasoning",
		"id": "rs_1",
		"summary": [
			{"type": "summary_text", "text": "Thinking about the answer..."}
		]
	}
	"""

	let data = jsonString.data(using: .utf8)!
	let decoder = JSONDecoder()
	let item = try decoder.decode(OutputItem.self, from: data)

	if case .reasoning(let reasoning) = item {
		#expect(reasoning.id == "rs_1")
		#expect(reasoning.summary?.count == 1)
		#expect(reasoning.summary?[0].text == "Thinking about the answer...")
	} else {
		Issue.record("Expected reasoning output item")
	}
}

@Test func testResponseObjectWithFunctionCalls() throws {
	let jsonString = """
	{
		"id": "resp_456",
		"object": "response",
		"created_at": 1700000000,
		"model": "gpt-4o",
		"output": [
			{
				"type": "function_call",
				"id": "fc_1",
				"call_id": "call_1",
				"name": "get_weather",
				"arguments": "{\\"location\\": \\"Paris\\"}",
				"status": "completed"
			},
			{
				"type": "function_call",
				"id": "fc_2",
				"call_id": "call_2",
				"name": "get_time",
				"arguments": "{\\"timezone\\": \\"CET\\"}",
				"status": "completed"
			}
		],
		"status": "completed"
	}
	"""

	let data = jsonString.data(using: .utf8)!
	let response = try JSONDecoder().decode(ResponseObject.self, from: data)

	#expect(response.requiresToolExecution == true)
	#expect(response.firstFunctionCalls?.count == 2)
	#expect(response.firstFunctionCalls?[0].name == "get_weather")
	#expect(response.firstFunctionCalls?[1].name == "get_time")
	#expect(response.firstOutputText == nil)
}

// MARK: - FunctionCallItem.decodeArguments Tests

@Test func testFunctionCallItemDecodeArguments() throws {
	struct WeatherArgs: Decodable {
		let location: String
		let unit: String
	}

	let call = FunctionCallItem(
		id: "fc_1",
		callId: "call_1",
		name: "get_weather",
		arguments: "{\"location\": \"Paris\", \"unit\": \"celsius\"}"
	)

	let args: WeatherArgs = try call.decodeArguments()
	#expect(args.location == "Paris")
	#expect(args.unit == "celsius")
}

// MARK: - ToolChoice Encoding Tests

@Test func testToolChoiceEncoding() throws {
	let encoder = JSONEncoder()

	// Auto
	let autoData = try encoder.encode(ToolChoice.auto)
	#expect(String(data: autoData, encoding: .utf8) == "\"auto\"")

	// None
	let noneData = try encoder.encode(ToolChoice.none)
	#expect(String(data: noneData, encoding: .utf8) == "\"none\"")

	// Required
	let requiredData = try encoder.encode(ToolChoice.required)
	#expect(String(data: requiredData, encoding: .utf8) == "\"required\"")

	// Function — Responses API format: {"type":"function","name":"get_weather"}
	let funcData = try encoder.encode(ToolChoice.function("get_weather"))
	let funcJson = try JSONSerialization.jsonObject(with: funcData) as? [String: Any]
	#expect(funcJson?["type"] as? String == "function")
	#expect(funcJson?["name"] as? String == "get_weather")
	// Should NOT have nested "function" object (unlike Chat Completions)
	#expect(funcJson?["function"] == nil)
}

// MARK: - InputBuilder Tests

@Test func testInputBuilderBasic() throws {
	let request = try ResponseRequest(model: "gpt-4o") {
		System("You are helpful.")
		User("Hello")
		Developer("Follow rules.")
	}

	if case .items(let items) = request.input {
		#expect(items.count == 3)
	} else {
		Issue.record("Expected items input")
	}
}

@Test func testInputBuilderWithFunctionOutput() throws {
	let request = try ResponseRequest(model: "gpt-4o") {
		User("What's the weather?")
		FunctionOutput(callId: "call_1", output: "{\"temp\": 72}")
	}

	if case .items(let items) = request.input {
		#expect(items.count == 2)
	} else {
		Issue.record("Expected items input")
	}
}

// MARK: - FunctionToolParam Tests

@Test func testFunctionToolParamStructure() throws {
	let tool = FunctionToolParam(
		name: "get_weather",
		description: "Get the current weather",
		parameters: .object(properties: ["location": .string(description: "City name")], required: ["location"])
	)

	#expect(tool.name == "get_weather")
	#expect(tool.type == "function")
	#expect(tool.description == "Get the current weather")
}

@Test func testFunctionToolParamEncoding() throws {
	let tool = FunctionToolParam(
		name: "calculate",
		description: "Perform calculation",
		parameters: .object(properties: ["expr": .string(description: "Expression")], required: ["expr"]),
		strict: true
	)

	let encoder = JSONEncoder()
	let data = try encoder.encode(tool)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["type"] as? String == "function")
	#expect(json?["name"] as? String == "calculate")
	#expect(json?["description"] as? String == "Perform calculation")
	#expect(json?["strict"] as? Bool == true)
}

// MARK: - Multiple Config Parameters

@Test func testMultipleConfigParameters() throws {
	let request = try ResponseRequest(model: "gpt-4o", config: {
		try Temperature(0.7)
		try MaxOutputTokens(150)
		try TopP(0.9)
		try FrequencyPenalty(0.5)
		try PresencePenalty(-0.2)
		try Instructions("Be helpful.")
		Reasoning(effort: .high)
		TruncationParam(.auto)
		ServiceTierParam(.flex)
		Metadata(["key": "value"])
		ParallelToolCalls(true)
	}, text: "Test")

	#expect(request.temperature == 0.7)
	#expect(request.maxOutputTokens == 150)
	#expect(request.topP == 0.9)
	#expect(request.frequencyPenalty == 0.5)
	#expect(request.presencePenalty == -0.2)
	#expect(request.instructions == "Be helpful.")
	#expect(request.reasoning?.effort == .high)
	#expect(request.truncation == .auto)
	#expect(request.serviceTier == .flex)
	#expect(request.metadata?["key"] == "value")
	#expect(request.parallelToolCalls == true)
}

// MARK: - ResponseInput Encoding

@Test func testResponseInputTextEncoding() throws {
	let request = try ResponseRequest(model: "gpt-4o", text: "Simple text")

	let encoder = JSONEncoder()
	let data = try encoder.encode(request)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["input"] as? String == "Simple text")
}

// MARK: - PreviousResponseId Config

@Test func testPreviousResponseIdConfig() throws {
	let request = try ResponseRequest(model: "gpt-4o", config: {
		try PreviousResponseId("resp_abc123")
	}, text: "Follow up question")

	#expect(request.previousResponseId == "resp_abc123")

	let encoder = JSONEncoder()
	let data = try encoder.encode(request)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	#expect(json?["previous_response_id"] as? String == "resp_abc123")
}

// MARK: - Reasoning Config

@Test func testReasoningConfigEncoding() throws {
	let request = try ResponseRequest(model: "gpt-4o", config: {
		Reasoning(effort: .high, summary: .auto)
	}, text: "Think deeply about this.")

	#expect(request.reasoning?.effort == .high)
	#expect(request.reasoning?.summary == .auto)

	let encoder = JSONEncoder()
	let data = try encoder.encode(request)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

	let reasoning = json?["reasoning"] as? [String: Any]
	#expect(reasoning?["effort"] as? String == "high")
	#expect(reasoning?["summary"] as? String == "auto")
}

// MARK: - Edge Cases

@Test func testEmptyInput() throws {
	let request = try ResponseRequest(model: "gpt-4o", input: [])

	if case .items(let items) = request.input {
		#expect(items.isEmpty)
	} else {
		Issue.record("Expected items input")
	}
}

@Test func testResponseObjectConvenienceExtensions() throws {
	let jsonString = """
	{
		"id": "resp_789",
		"object": "response",
		"created_at": 1700000000,
		"model": "gpt-4o",
		"output": [],
		"status": "completed",
		"usage": {
			"input_tokens": 5,
			"output_tokens": 0,
			"total_tokens": 5
		}
	}
	"""

	let data = jsonString.data(using: .utf8)!
	let response = try JSONDecoder().decode(ResponseObject.self, from: data)

	#expect(response.firstOutputText == nil)
	#expect(response.firstFunctionCalls == nil)
	#expect(response.requiresToolExecution == false)
	#expect(response.totalTokens == 5)
}

// MARK: - StreamEvent New Case Tests

@Test func testStreamEventFunctionCallDeltaCase() {
	let event = StreamEvent.functionCallArgumentsDelta(delta: "{\"loc", callId: "call_99", index: 0)

	if case .functionCallArgumentsDelta(let delta, let callId, let index) = event {
		#expect(delta == "{\"loc")
		#expect(callId == "call_99")
		#expect(index == 0)
	} else {
		Issue.record("Expected functionCallArgumentsDelta case")
	}
}

@Test func testStreamEventFunctionCallDoneCase() {
	let event = StreamEvent.functionCallArgumentsDone(arguments: "{\"location\":\"Paris\"}", callId: "call_42", index: 1)

	if case .functionCallArgumentsDone(let arguments, let callId, let index) = event {
		#expect(arguments == "{\"location\":\"Paris\"}")
		#expect(callId == "call_42")
		#expect(index == 1)
	} else {
		Issue.record("Expected functionCallArgumentsDone case")
	}
}

// MARK: - ToolSessionEvent Tests

@Test func testToolSessionEventIterationStarted() {
	let event = ToolSessionEvent.iterationStarted(2)

	if case .iterationStarted(let iteration) = event {
		#expect(iteration == 2)
	} else {
		Issue.record("Expected iterationStarted case")
	}
}

@Test func testToolSessionEventToolCallStarted() {
	let event = ToolSessionEvent.toolCallStarted(callId: "call_7", name: "get_weather", arguments: "{\"city\":\"London\"}")

	if case .toolCallStarted(let callId, let name, let arguments) = event {
		#expect(callId == "call_7")
		#expect(name == "get_weather")
		#expect(arguments == "{\"city\":\"London\"}")
	} else {
		Issue.record("Expected toolCallStarted case")
	}
}

@Test func testToolSessionEventToolCallCompleted() {
	let duration = Duration.milliseconds(250)
	let event = ToolSessionEvent.toolCallCompleted(callId: "call_8", name: "get_weather", output: "Sunny, 22°C", duration: duration)

	if case .toolCallCompleted(let callId, let name, let output, let d) = event {
		#expect(callId == "call_8")
		#expect(name == "get_weather")
		#expect(output == "Sunny, 22°C")
		#expect(d == duration)
	} else {
		Issue.record("Expected toolCallCompleted case")
	}
}

@Test func testToolSessionEventUsageUpdate() {
	let usage = ResponseObject.Usage(inputTokens: 100, outputTokens: 50, totalTokens: 150)
	let event = ToolSessionEvent.usageUpdate(usage, iteration: 2)

	if case .usageUpdate(let u, let iteration) = event {
		#expect(u.inputTokens == 100)
		#expect(u.outputTokens == 50)
		#expect(u.totalTokens == 150)
		#expect(iteration == 2)
	} else {
		Issue.record("Expected usageUpdate case")
	}
}

@Test func testToolSessionResultTotalUsage() throws {
	let jsonString = """
	{
		"id": "resp_1", "object": "response", "created_at": 1700000000,
		"model": "gpt-4o", "output": [], "status": "completed"
	}
	"""
	let response = try JSONDecoder().decode(ResponseObject.self, from: Data(jsonString.utf8))
	let usage1 = ResponseObject.Usage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
	let usage2 = ResponseObject.Usage(inputTokens: 20, outputTokens: 10, totalTokens: 30)

	let result = ToolSessionResult(response: response, iterations: 2, log: [], iterationUsages: [usage1, usage2])

	let total = result.totalUsage
	#expect(total != nil)
	#expect(total!.inputTokens == 30)
	#expect(total!.outputTokens == 15)
	#expect(total!.totalTokens == 45)
}

@Test func testToolSessionResultTotalUsageEmpty() throws {
	let jsonString = """
	{
		"id": "resp_1", "object": "response", "created_at": 1700000000,
		"model": "gpt-4o", "output": [], "status": "completed"
	}
	"""
	let response = try JSONDecoder().decode(ResponseObject.self, from: Data(jsonString.utf8))

	let result = ToolSessionResult(response: response, iterations: 1, log: [], iterationUsages: [])
	#expect(result.totalUsage == nil)
}

// MARK: - Reasoning Stream Events

@Test func testUsageWithReasoningTokens() throws {
	let json = """
	{
	  "id": "resp_1", "object": "response", "created_at": 0, "model": "o3-mini",
	  "output": [], "status": "completed",
	  "usage": {
	    "input_tokens": 10, "output_tokens": 50, "total_tokens": 60,
	    "output_tokens_details": { "reasoning_tokens": 40 }
	  }
	}
	"""
	let response = try JSONDecoder().decode(ResponseObject.self, from: Data(json.utf8))
	#expect(response.usage?.outputTokensDetails?.reasoningTokens == 40)
}

@Test func testReasoningSummaryStreamEvents() {
	let addedEvent = StreamEvent.reasoningSummaryPartAdded(
		part: ReasoningSummary(type: "summary_text", text: "thinking..."),
		index: 0,
		summaryIndex: 0
	)

	if case .reasoningSummaryPartAdded(let part, let index, let summaryIndex) = addedEvent {
		#expect(part.text == "thinking...")
		#expect(part.type == "summary_text")
		#expect(index == 0)
		#expect(summaryIndex == 0)
	} else {
		Issue.record("Expected reasoningSummaryPartAdded case")
	}

	let doneEvent = StreamEvent.reasoningSummaryPartDone(
		part: ReasoningSummary(type: "summary_text", text: "done thinking"),
		index: 0,
		summaryIndex: 0
	)

	if case .reasoningSummaryPartDone(let part, let index, let summaryIndex) = doneEvent {
		#expect(part.text == "done thinking")
		#expect(part.type == "summary_text")
		#expect(index == 0)
		#expect(summaryIndex == 0)
	} else {
		Issue.record("Expected reasoningSummaryPartDone case")
	}
}

// MARK: - Reasoning Convenience

@Test func testReasoningItemSummaryText() {
	let item = ReasoningItem(
		id: "rs_1",
		summary: [
			ReasoningSummary(type: "summary_text", text: "First thought"),
			ReasoningSummary(type: "summary_text", text: "Second thought"),
		]
	)
	#expect(item.summaryText == "First thought\nSecond thought")

	let emptyItem = ReasoningItem(id: "rs_2", summary: [])
	#expect(emptyItem.summaryText == nil)

	let nilItem = ReasoningItem(id: "rs_3")
	#expect(nilItem.summaryText == nil)
}

@Test func testReasoningItemContentText() {
	let item = ReasoningItem(
		id: "rs_1",
		content: [
			ReasoningContent(type: "reasoning_text", text: "Raw trace A"),
			ReasoningContent(type: "reasoning_text", text: "Raw trace B"),
		]
	)
	#expect(item.contentText == "Raw trace A\nRaw trace B")

	let emptyItem = ReasoningItem(id: "rs_2", content: [])
	#expect(emptyItem.contentText == nil)

	let nilItem = ReasoningItem(id: "rs_3")
	#expect(nilItem.contentText == nil)
}

@Test func testResponseObjectReasoningExtensions() throws {
	let json = """
	{
	  "id": "resp_1", "object": "response", "created_at": 0, "model": "o3-mini",
	  "output": [
	    {
	      "type": "reasoning",
	      "id": "rs_1",
	      "summary": [{"type": "summary_text", "text": "Thinking..."}]
	    }
	  ],
	  "status": "completed",
	  "usage": {
	    "input_tokens": 10, "output_tokens": 50, "total_tokens": 60,
	    "output_tokens_details": { "reasoning_tokens": 40 }
	  }
	}
	"""
	let response = try JSONDecoder().decode(ResponseObject.self, from: Data(json.utf8))

	#expect(response.reasoningItems.count == 1)
	#expect(response.firstReasoningItem != nil)
	#expect(response.firstReasoningItem?.id == "rs_1")
	#expect(response.reasoningTokens == 40)
}

@Test func testTranscriptEntryReasoningCase() {
	let item = ReasoningItem(
		id: "rs_1",
		summary: [ReasoningSummary(type: "summary_text", text: "Some thought")]
	)
	let entry = TranscriptEntry.reasoning(item)

	if case .reasoning(let r) = entry {
		#expect(r.id == "rs_1")
		#expect(r.summaryText == "Some thought")
	} else {
		Issue.record("Expected reasoning case")
	}
}

@Test func testToolSessionEventLLMWrapper() throws {
	let jsonString = """
	{
		"id": "resp_stream",
		"object": "response",
		"created_at": 1700000000,
		"model": "gpt-4o",
		"output": [],
		"status": "completed"
	}
	"""
	let response = try JSONDecoder().decode(ResponseObject.self, from: Data(jsonString.utf8))
	let innerEvent = StreamEvent.responseCompleted(response)
	let event = ToolSessionEvent.llm(innerEvent)

	if case .llm(let streamEvent) = event,
	   case .responseCompleted(let r) = streamEvent {
		#expect(r.id == "resp_stream")
	} else {
		Issue.record("Expected llm(.responseCompleted) case")
	}
}
