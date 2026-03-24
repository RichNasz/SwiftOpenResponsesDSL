# Spec-Driven Development with SwiftOpenResponsesDSL

## What Is Spec-Driven Development?

Spec-driven development (SDD) is a workflow where you write specifications before code. You describe what your LLM application should do (WHAT spec) and how to implement it with SwiftOpenResponsesDSL (HOW spec), then hand the specs to an AI coding agent to generate the implementation.

SDD is entirely optional. You can use SwiftOpenResponsesDSL without writing any specs. But if you use an AI coding agent, specs reduce back-and-forth and produce more accurate results on the first pass.

## The Three Tools

### WHAT Specs -- Define the Product

A WHAT spec describes what the application does from the user's perspective. It lists the model, tools needed, conversation requirements, streaming needs, and acceptance criteria.

A WHAT spec does not prescribe implementation. It answers: *what should exist when this is done?*

Write a WHAT spec when you are building a new LLM-powered feature or changing requirements for an existing one.

### HOW Specs -- Guide the Implementation

A HOW spec translates WHAT requirements into technical decisions. It specifies whether to use ToolSession or Agent, which configuration parameters to set, how to wire tools, streaming event handling patterns, and error handling strategy.

A HOW spec gives the AI agent enough detail to generate code without ambiguity. It answers: *how should this be built using SwiftOpenResponsesDSL?*

Write a HOW spec after the WHAT spec is settled, before asking an agent to generate code.

### Agent Skills -- Provide Package Knowledge

[Agent Skills](https://agentskills.io) give the AI coding agent domain-specific knowledge about a package. SwiftOpenResponsesDSL ships two complementary skills:

**`using-swift-open-responses-dsl`** (reference skill) teaches the agent what the package provides:

- Client setup, request construction, and response handling
- All configuration parameters and their validation rules
- Tool calling, ToolSession, and Agent APIs
- Streaming events and reasoning model support
- Common pitfalls and naming differences from other DSLs

**`design-responses-app`** (process skill) teaches the agent how to design a complete application:

- A 7-step decision workflow: interaction pattern, model, tools, config, streaming, errors, assembly
- Explicit decision rules for each choice (not just options, but when to use each)
- Where DSL wiring ends and tool design begins

For tool design (the `@LLMTool` structs themselves), consult the skills from [SwiftLLMToolMacros](https://github.com/RichNasz/SwiftLLMToolMacros): `using-swift-llm-tool-macros` (reference) and `design-llm-tool` (process).

Without the skills, the agent relies on general training, which may be outdated or incomplete. With the skills loaded, the agent knows the current API surface and the correct design process.

See the [README](../README.md#installing-the-skills) for installation instructions.

## How They Work Together

Each tool covers a different layer. Together they form a complete pipeline from requirements to working code:

1. **You write a WHAT spec** -- "I want a weather assistant that uses tools, supports multi-turn chat, and streams responses"
2. **You write a HOW spec** -- "Use Agent with `@SessionBuilder`, wire GetWeather via AgentTool, stream with `.contentPartDelta` handling, add RequestTimeout(120)"
3. **The agent reads the HOW spec and has the Skills loaded** -- it knows both *your* requirements and *the package's* API, so it generates correct Swift code
4. **You review and run `swift build && swift test`** -- verify the output matches the WHAT spec's acceptance criteria

The WHAT spec is durable -- it survives package version changes because it describes behavior, not API. The HOW spec is version-specific -- it references current type names and patterns. The Skill ensures the agent knows the current API even if the HOW spec has a gap.

## Graceful Degradation

### Without the Skills

The agent can still follow a HOW spec, but may confuse SwiftOpenResponsesDSL with SwiftChatCompletionsDSL patterns (e.g., using `messages:` instead of `input:`, `systemPrompt:` instead of `instructions:`). A detailed HOW spec compensates partially, but the Skills make the agent fluent.

### Without Specs

The agent can still use the Skills to build applications from a natural-language description. This works well for simple integrations. For complex applications with multiple tools, reasoning models, streaming, and error handling, specs prevent miscommunication and serve as a reviewable contract.

### Without Both

You write code manually using the [README](../README.md) as reference. The DSL works the same regardless of workflow.

## Getting Started

1. **Install the Agent Skills** (optional) -- copy the skill folders from `.build/checkouts/` into your project's `skills/` directory. This includes both DSL skills (`using-swift-open-responses-dsl`, `design-responses-app`) and macro skills (`using-swift-llm-tool-macros`, `design-llm-tool`). See the [README](../README.md#installing-the-skills) for exact commands and Claude Code setup instructions.

2. **Write a WHAT spec** -- describe the application, its tools, conversation requirements, and acceptance criteria. See [`Examples/Specs/WeatherAssistant-WHAT.md`](../Examples/Specs/WeatherAssistant-WHAT.md) for a template.

3. **Write a HOW spec** -- translate the WHAT into DSL-specific implementation guidance. See [`Examples/Specs/WeatherAssistant-HOW.md`](../Examples/Specs/WeatherAssistant-HOW.md) for a template.

4. **Ask your agent to implement** -- point the agent at the HOW spec and review the generated code. In Claude Code, you can invoke the skill directly with `/skill design-responses-app` to ensure the agent has the correct design process loaded.

## Example

See the complete worked example in [`Examples/Specs/`](../Examples/Specs/):

- [WeatherAssistant-WHAT.md](../Examples/Specs/WeatherAssistant-WHAT.md) -- Product requirements for a weather assistant
- [WeatherAssistant-HOW.md](../Examples/Specs/WeatherAssistant-HOW.md) -- Implementation guidance using SwiftOpenResponsesDSL
