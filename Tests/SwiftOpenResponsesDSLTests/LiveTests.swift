//
//  LiveTests.swift
//  SwiftOpenResponsesDSL
//
//  Live integration tests against a local LLM server.
//  Set OPENRESPONSES_BASE_URL and OPENRESPONSES_MODEL env vars to configure.
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
		ProcessInfo.processInfo.environment["OPENRESPONSES_MODEL"] ?? "nvidia/nemotron-3-nano"
	}()

	static let endpointURL: String = {
		baseURL.hasSuffix("/") ? "\(baseURL)v1/responses" : "\(baseURL)/v1/responses"
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
}
