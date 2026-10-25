# Swift Package Documentation Specification: SwiftOpenResponsesDSL

## Overview
This document specifies the documentation requirements for the package named SwiftOpenResponsesDSL.

## Requirements
- **Documentation**: Include a README.md with an overview of the project, a summary of what a DSL is, a description of the DSL in the package, and simple usage examples that includes streaming and non-streaming responses. Use DocC for comprehensive documentation.

## README.md Structure
The root README.md file must include the following sections in order:

1. **Package Title and Badge Section**
   - Project name and brief tagline
   - Swift version badge, platform badges, license badge
   - A "Built with Grok Build" badge linking to the Grok Build repository (`https://github.com/xai-org/grok-build`). Shields.io has no Grok logo, so the badge is text-only.
   - No "Built with Claude Code" badge. That badge reads as the current toolchain. Claude Code created the project initially; say that in one sentence under the tagline, and state that ongoing maintenance uses Grok Build and the latest Grok model available.

2. **Overview Section**
   - Clear description of what SwiftOpenResponsesDSL does
   - Brief explanation of the Open Responses API
   - Key benefits and use cases, including text inference from Open Responses 2026-04-24: `top_logprobs`, `safety_identifier`, `prompt_cache_key`, `stream_options`, assistant message `phase`, output-text logprobs, and the text streaming events (`output_text.done`, refusal, annotation, reasoning text, reasoning-summary text)
   - A comment that a Responses endpoint may not implement the full specification. Use LM Studio local testing as the example: `swift test` against `http://127.0.0.1:1234` and `openai/gpt-oss-20b`, with a link to `Spec/LiveTesting.md`. Name the gaps that server shows: omitted `safety_identifier` and `prompt_cache_key`, rewritten `frequency_penalty` and `service_tier`, HTTP 400 on `item_reference` and object `tool_choice`, ignored JSON `text.format`, empty `logprobs`, and reasoning on the completed response without reasoning deltas. Point to `Spec/SwiftOpenResponsesDSL.md` for the client contract. Do not copy the live-test tables into the README.
   - A short note that this package does not cover every Open Responses surface. Name WebSocket transport, context compaction (`POST /v1/responses/compact`), file and video input, reasoning-item round-trip, and non-string tool output. State that unknown output item types fail decoding and are not ignored. Streaming in the examples is HTTP SSE. Link [`Spec/Unimplemented.md`](Unimplemented.md). Do not copy that page's tables or its uptake note into the README. Do not describe those package gaps as server limits.
   - A short note that other Open Responses elements are optional and relevant: assistant `phase`, output-text `logprobs`, and the request configuration fields. A server may omit them. Link [Optional spec elements](SwiftOpenResponsesDSL.md#optional-spec-elements). Do not copy that list into the README.

3. **Quick Start Section**
   - Installation instructions (Swift Package Manager)
   - Minimal working example

4. **Usage Examples Section**
   - Basic non-streaming example with explanation
   - Basic streaming example with explanation
   - Conversation continuity with previous_response_id
   - Tool calling example

5. **Requirements Section**
   - Swift version requirements
   - Platform support (macOS, iOS versions)
   - Dependencies

## DocC Documentation
All public APIs in source files must include triple-slash (///) comments following Apple standards.

The DocC catalog landing page is `Sources/SwiftOpenResponsesDSL/SwiftOpenResponsesDSL.docc/SwiftOpenResponsesDSL.md`. It must stay aligned with the README overview: what a DSL is, the Open Responses HTTP client, the 2026-04-24 text-inference surface, optional spec elements (assistant `phase`, output-text `logprobs`, and the other request configuration fields, with a pointer to `Spec/SwiftOpenResponsesDSL.md`), the LM Studio live-test example (`swift test`, `http://127.0.0.1:1234`, `openai/gpt-oss-20b`, and the same gaps named in the README), and a note that the package does not cover every Open Responses surface. That note names WebSocket transport, `POST /v1/responses/compact`, file and video input, reasoning-item round-trip, and non-string tool output, states that unknown output item types fail decoding, and links `Spec/Unimplemented.md`. Do not copy the live-test tables, the unimplemented tables, or the uptake note into the catalog. Symbol comments on ``LLMClient``, ``ResponseRequest``, ``StreamEvent``, ``AssistantPhase``, ``TopLogprobs``, ``SafetyIdentifier``, ``PromptCacheKey``, ``StreamOptions``, and ``OutputTextContent`` must carry the same optional-field and HTTP-only facts.

### API Documentation Standards
All public APIs must include comprehensive triple-slash comments following this structure:

```swift
/// Brief summary of what the function/type does.
///
/// - Parameters:
///   - parameterName: Description
/// - Returns: Description
/// - Throws: List of specific errors
public func someMethod(parameter: String) throws -> ResultType
```

### Code Example Standards
All code examples in documentation must follow these standards:
- **Language Tags**: Always specify `swift` for Swift code blocks
- **Complete Examples**: Provide runnable code when possible
- **Error Handling**: Show proper error handling patterns
- **Formatting**: Use consistent indentation (tab) and Swift naming conventions

## Agent Skills

### `skills/using-swift-open-responses-dsl/SKILL.md`

An [Agent Skill](https://agentskills.io) that gives AI coding assistants package-specific context for using SwiftOpenResponsesDSL.

### Required Content

The SKILL.md must include:

- YAML frontmatter with `name` (kebab-case, gerund form) and `description` (third-person, under 1024 chars, includes trigger keywords)
- Installation snippet (SPM dependency + imports)
- LLMClient initialization
- Basic request examples (text and structured input)
- Convenience input functions table (`System`, `Developer`, `User`, `UserImage`, `FunctionOutput`, `Assistant` with `phase` and optional `id`)
- Configuration parameters reference table (all `ResponseConfigParameter` types with init syntax, range, and whether `try` is required), including `TopLogprobs`, `SafetyIdentifier`, `PromptCacheKey`, and `StreamOptions`
- Conversation continuity with `PreviousResponseId`
- Reasoning models section (effort levels, summary types, accessing reasoning output, streaming events including `reasoningDelta`, `reasoningDone`, `reasoningSummaryTextDelta`, and `reasoningSummaryTextDone`)
- Text streaming: `contentPartDelta` still fires for `response.output_text.delta`; `outputTextDelta` (optional logprobs), `outputTextDone`, `refusalDelta`, `refusalDone`, and `outputTextAnnotationAdded`
- Structured output section (`TextConfig`, `TextParam`, `TextFormat`, including JSON Schema `description`)
- Tool calling (macro-powered and manual, `AgentTool` bridging, `ToolChoice`, `ToolsBuilder`)
- ToolSession (declarative/explicit init, run, streaming with correct enum case patterns, `ToolSessionResult` with `ToolCallLogEntry`)
- Agent (declarative/explicit init, methods with `await`, state, transcript including `.reasoning`)
- Error handling (`LLMError` cases)
- Common pitfalls (naming differences from SwiftChatCompletionsDSL, continuity model differences, config params that throw, assistant `phase`, and partial server support)
- Partial server support pitfall: a Responses endpoint may not implement the full spec. This pitfall is about fields the client does send. Say that a server may omit assistant `phase`, output-text `logprobs`, and the other request configuration fields. Cite LM Studio local testing (`http://127.0.0.1:1234`, `openai/gpt-oss-20b`) and point to `Spec/LiveTesting.md` for the field list and to `Spec/SwiftOpenResponsesDSL.md` for the optional-element list. Name the kinds of gaps (omitted or rewritten echoes, HTTP 400, ignored JSON format, empty logprobs, reasoning without reasoning deltas). Do not paste the live-test tables or the optional-element list into the skill. Do not put WebSocket, compaction, or other package gaps in this pitfall.
- Out of scope section referencing companion skills, and stating that the package does not cover every Open Responses surface. Name WebSocket transport, `POST /v1/responses/compact`, file and video input, reasoning-item round-trip, and non-string tool output. State that unknown output item types fail decoding and are not ignored. Point to `Spec/Unimplemented.md`. Do not copy that page's tables or its uptake note. Streaming examples stay HTTP SSE.

### Constraints

- Body must be under 500 lines
- No reference files — the API surface fits within the SKILL.md itself
- Only covers package-specific knowledge; assumes the agent already knows Swift
- Code examples must use correct enum case patterns matching actual source types

### `skills/design-responses-app/SKILL.md`

A companion process skill that teaches AI coding assistants *how to design* an application using SwiftOpenResponsesDSL, as opposed to the reference skill which teaches *what the APIs do*. Use when generating new application code from requirements or specs.

### Required Content

The SKILL.md must include:

- YAML frontmatter with `name` (kebab-case) and `description` (third-person, describes its process-skill role and trigger context)
- A sequential, numbered design process covering: choosing the interaction pattern (one-shot vs ToolSession vs Agent with decision rules); selecting and configuring the model (including reasoning, and a note that a Responses server may not implement the full spec, with LM Studio local testing in `Spec/LiveTesting.md` as the example — do not restate that file's field table); defining tools (macro vs manual with decision rules); composing configuration parameters; choosing streaming vs non-streaming (with decision rules); structuring error handling; assembling the final code with a pre-flight checklist
- Decision rules must be explicit — not just "here are the options" but "use X when Y"
- A complete worked example demonstrating Agent with streaming, tool calling, and multi-turn continuity
- An explicit boundary section stating that tool design (`@LLMTool` structs) is out of scope and directing to the SwiftLLMToolMacros skills. The same boundary states that the package does not cover every Open Responses surface. Name WebSocket transport, `POST /v1/responses/compact`, file and video input, reasoning-item round-trip, and non-string tool output. State that unknown output item types fail decoding and are not ignored. Point to `Spec/Unimplemented.md` instead of repeating its uptake note or its tables. When a design needs a shorter context window, send a shorter `input`.

### Constraints

- Must not duplicate `using-swift-open-responses-dsl` content; the two skills are complementary, not overlapping
- Must not cover `@LLMTool` struct design — those belong in the `design-llm-tool` skill from SwiftLLMToolMacros
- Scoped to DSL wiring decisions only

### README Agent Skill Section

The README's "Agent Skill" section must:

- State that skills are optional and not required to use the package
- Note that only agents implementing the [agentskills.io](https://agentskills.io) spec can use skills
- List every skill in the `skills/` directory by name with its role (reference vs process) — a table is preferred
- Explain that adding an SPM dependency does not make skills discoverable — SPM downloads sources into `.build/checkouts/`, which agents don't scan
- Include a `swift package resolve` step, then `mkdir -p skills` before the Claude Code copy commands and `mkdir -p .grok/skills` before the Grok Build copy commands
- Provide individual install commands for each skill (one `cp` per skill directory), covering both this package's skills AND the SwiftLLMToolMacros dependency's skills, once into `skills/` and once into `.grok/skills/`
- Show a summary table of all four skills with their source package and role
- Include a "Using Skills with Grok Build" subsection explaining: automatic discovery from `.grok/skills/`, manual invocation via `/using-swift-open-responses-dsl` and `/design-responses-app`, verification with `grok inspect`, and an `AGENTS.md` or `[skills] paths` fallback for non-standard layouts
- Include a "Using Skills with Claude Code" subsection explaining: automatic discovery from `skills/`, manual invocation via `/skill`, verification, and `CLAUDE.md` fallback for non-standard layouts
- Include a "Spec-Driven Development" subsection linking to `docs/SpecDrivenDevelopment.md` and `Examples/Specs/`

## Unimplemented Open Responses surfaces

### `Spec/Unimplemented.md`

The inventory of Open Responses 2026-04-24 functionality this package does not implement. It is the canonical list. Other docs link it. They do not copy its tables or its uptake note.

### Required sections

1. **What this page is** — Inventory of package gaps, the check date, Open Responses spec version 2026-04-24, and links to the specification, `openapi.json`, and the reference. Point to `Spec/SwiftOpenResponsesDSL.md` for the implemented client contract.
2. **Three kinds of gap** — Package gap, server gap (link Server compatibility and `Spec/LiveTesting.md`), and features that are not in Open Responses 2026-04-24. The third kind names response retrieve, cancel, and delete, the conversations API, hosted tools, audio input, MCP, and `file_id`, without describing how to call them. State that `application/json` is the required request encoding.
3. **Not implemented** — Grouped tables for transport, compaction, input items and content, and tool results. Each row names the surface, the Open Responses schema or endpoint, and what a caller does today. WebSocket and compaction each keep a short uptake note: optional in the specification, shipped by OpenAI, not documented by the local servers this package tests, revisit when the LM Studio host in `Spec/LiveTesting.md` documents them.
4. **Decoded narrowly** — Fail-closed and drop behavior: unknown output item types throw, output content other than `output_text` and `refusal` throws, `function_call_output` inside `output` does not decode as a tool result, a streaming `error` event keeps `message` only, and `obfuscation` on deltas is not surfaced. Say that unknown keys on a decoded type are ignored. Do not call unknown types ignored.
5. **Maintenance** — When `openapi.json` `info.version` changes, update this page in the same change as `Spec/SwiftOpenResponsesDSL.md`. A schema is described in the client spec or named here. Enums and streaming-event schemas count as described when the client spec names the JSON values or event names they wrap.

### Constraints

- Tone matches `Spec/SwiftOpenResponsesDSL.md`: direct, no roadmap.
- Do not list fields the client already sends and decodes.
- `Spec/LiveTesting.md` links this page. The live suite does not call the missing endpoints.

## Spec-Driven Development

### docs/SpecDrivenDevelopment.md

### Required Sections

1. **What Is Spec-Driven Development?** — Definition and opt-in framing
2. **The Three Tools** — Subsections for WHAT Specs, HOW Specs, and Agent Skills
3. **How They Work Together** — Narrative showing the workflow from spec to generated code
4. **Graceful Degradation** — What works without the Skills, what works without specs
5. **Getting Started** — Numbered steps (install skills, write WHAT, write HOW, ask agent)
6. **Example** — Links to sample specs in `Examples/Specs/`

### Constraints

- Must frame SDD as optional, not prescriptive
- Must not duplicate SKILL.md content; link to it instead
- Must link to sample specs in `Examples/Specs/`
- Tone: direct, practical, no methodology evangelism

## Examples/Specs/

### Purpose

Sample WHAT and HOW specs demonstrating how a package consumer would use spec-driven development to build an application using SwiftOpenResponsesDSL.

### Required Files

- `WeatherAssistant-WHAT.md` — WHAT spec for a weather assistant application
- `WeatherAssistant-HOW.md` — HOW spec for the same application

### WHAT Spec Requirements

- Must define model, tools (with argument tables), conversation requirements, streaming requirements, and acceptance criteria
- Must include at least one tool with required and optional arguments
- Must specify multi-turn conversation requirements

### HOW Spec Requirements

- Must reference SwiftOpenResponsesDSL and SwiftLLMToolMacros by import name
- Must explain the ToolSession vs Agent decision with rationale
- Must show tool setup, agent configuration, streaming event handling, and error handling
- Must cover multi-turn continuity
