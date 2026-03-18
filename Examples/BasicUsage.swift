//
//  BasicUsage.swift
//  SwiftOpenResponsesDSL
//
//  Created by Richard Naszcyniec on 3/18/26.
//  Code assisted by AI
//
//  NOTE: This file contains usage examples. It is NOT compiled as part of the package.
//

import SwiftOpenResponsesDSL

// MARK: - Non-Streaming Text Input

func basicTextRequest() async throws {
	let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")

	let response = try await client.send(
		try ResponseRequest(model: "gpt-4o", config: {
			try Temperature(0.7)
			try MaxOutputTokens(150)
		}, text: "Explain Swift concurrency in one paragraph.")
	)

	print(response.firstOutputText ?? "No response")
	print("Tokens used: \(response.totalTokens)")
}

// MARK: - Structured Input with System Prompt

func structuredInputRequest() async throws {
	let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")

	let response = try await client.send(
		try ResponseRequest(model: "gpt-4o", config: {
			try Temperature(0.5)
			try Instructions("You are a coding assistant.")
		}) {
			System("You are a coding assistant specializing in Swift.")
			User("How do I use result builders?")
		}
	)

	print(response.firstOutputText ?? "No response")
}

// MARK: - Streaming

func streamingRequest() async throws {
	let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")

	let stream = client.stream(
		try ResponseRequest(model: "gpt-4o", stream: true, config: {
			try Temperature(0.8)
		}, text: "Write a short poem about Swift programming.")
	)

	for try await event in stream {
		switch event {
		case .contentPartDelta(let delta, _, _):
			print(delta, terminator: "")
		case .responseCompleted(let response):
			print("\n\nTokens: \(response.totalTokens)")
		default:
			break
		}
	}
}

// MARK: - Conversation Continuity

func conversationContinuity() async throws {
	let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")

	// First message
	let response1 = try await client.send(
		try ResponseRequest(model: "gpt-4o", text: "What is Swift?")
	)
	print("Response 1: \(response1.firstOutputText ?? "")")

	// Follow-up using previous_response_id
	let response2 = try await client.send(
		try ResponseRequest(model: "gpt-4o", config: {
			PreviousResponseId(response1.id)
		}, text: "Tell me more about its type system.")
	)
	print("Response 2: \(response2.firstOutputText ?? "")")
}

// MARK: - Tool Calling with ToolSession

func toolCallingExample() async throws {
	let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")

	let weatherTool = FunctionToolParam(
		name: "get_weather",
		description: "Get current weather for a location",
		parameters: .object(
			properties: [
				"location": .string(description: "City and state, e.g. Paris, France"),
			],
			required: ["location"]
		)
	)

	let session = ToolSession(client: client, model: "gpt-4o") {
		System("You are a weather assistant.")
		AgentTool(tool: weatherTool) { args in
			return "{\"temperature\": 72, \"condition\": \"sunny\"}"
		}
	}

	let result = try await session.run("What's the weather in Paris?")
	print(result.response.firstOutputText ?? "")
	print("Tool iterations: \(result.iterations)")
}

// MARK: - Agent with Persistent Conversation

func agentExample() async throws {
	let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")

	let weatherTool = FunctionToolParam(
		name: "get_weather",
		description: "Get current weather for a location",
		parameters: .object(
			properties: [
				"location": .string(description: "City name"),
			],
			required: ["location"]
		)
	)

	let agent = try Agent(client: client, model: "gpt-4o") {
		System("You are a helpful weather assistant.")
		AgentTool(tool: weatherTool) { args in
			return "{\"temperature\": 72, \"condition\": \"sunny\"}"
		}
	}

	let response1 = try await agent.run("Weather in Paris?")
	print("Response 1: \(response1)")

	let response2 = try await agent.run("What about London?")
	print("Response 2: \(response2)")

	// View agent transcript for debugging
	for entry in await agent.transcript {
		switch entry {
		case .userMessage(let msg):
			print("User: \(msg)")
		case .assistantMessage(let msg):
			print("Assistant: \(msg)")
		case .toolCall(let name, let args):
			print("Tool call: \(name)(\(args))")
		case .toolResult(let name, let result, let duration):
			print("Tool result: \(name) -> \(result) (\(duration))")
		case .error(let msg):
			print("Error: \(msg)")
		}
	}
}

// MARK: - Reasoning

func reasoningExample() async throws {
	let client = try LLMClient(baseURL: "https://api.openai.com/v1/responses", apiKey: "sk-...")

	let response = try await client.send(
		try ResponseRequest(model: "o3-mini", config: {
			Reasoning(effort: .high, summary: .auto)
			try MaxOutputTokens(2000)
		}, text: "Solve this step by step: What is the integral of x^2 * sin(x)?")
	)

	print(response.firstOutputText ?? "No response")
}
