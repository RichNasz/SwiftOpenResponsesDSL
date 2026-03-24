# Swift Package Documentation Specification: SwiftOpenResponsesDSL

## Overview
This document specifies the documentation requirements for the package named SwiftOpenResponsesDSL.

## Requirements
- **Documentation**: Include a README.md with an overview of the project, a summary of what a DSL is, a description of the DSL in the package, and simple usage examples that includes streaming and non-streaming responses. Use DocC for comprehensive documentation.

## README.md Structure
The root README.md file must include the following sections in order:

1. **Package Title and Badge Section**
   - Project name and brief tagline
   - Swift version badge, platform badges

2. **Overview Section**
   - Clear description of what SwiftOpenResponsesDSL does
   - Brief explanation of the Open Responses API
   - Key benefits and use cases

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
- Convenience input functions table (`System`, `Developer`, `User`, `UserImage`, `FunctionOutput`)
- Configuration parameters reference table (all `ResponseConfigParameter` types with init syntax, range, and whether `try` is required)
- Conversation continuity with `PreviousResponseId`
- Reasoning models section (effort levels, summary types, accessing reasoning output, streaming events)
- Structured output section (`TextConfig`, `TextParam`, `TextFormat`)
- Tool calling (macro-powered and manual, `AgentTool` bridging, `ToolChoice`, `ToolsBuilder`)
- ToolSession (declarative/explicit init, run, streaming with correct enum case patterns, `ToolSessionResult` with `ToolCallLogEntry`)
- Agent (declarative/explicit init, methods with `await`, state, transcript including `.reasoning`)
- Error handling (`LLMError` cases)
- Common pitfalls (naming differences from SwiftChatCompletionsDSL, continuity model differences, config params that throw)
- Out of scope section referencing companion skills

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
- A sequential, numbered design process covering: choosing the interaction pattern (one-shot vs ToolSession vs Agent with decision rules); selecting and configuring the model (including reasoning); defining tools (macro vs manual with decision rules); composing configuration parameters; choosing streaming vs non-streaming (with decision rules); structuring error handling; assembling the final code with a pre-flight checklist
- Decision rules must be explicit — not just "here are the options" but "use X when Y"
- A complete worked example demonstrating Agent with streaming, tool calling, and multi-turn continuity
- An explicit boundary section stating that tool design (`@LLMTool` structs) is out of scope and directing to the SwiftLLMToolMacros skills

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
- Include a `swift package resolve` step and `mkdir -p skills` before the copy commands
- Provide individual install commands for each skill (one `cp` per skill directory), covering both this package's skills AND the SwiftLLMToolMacros dependency's skills
- Show a summary table of all four skills with their source package and role
- Include a "Using Skills with Claude Code" subsection explaining: automatic discovery from `skills/`, manual invocation via `/skill`, verification, and `CLAUDE.md` fallback for non-standard layouts
- Include a "Spec-Driven Development" subsection linking to `docs/SpecDrivenDevelopment.md` and `Examples/Specs/`

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
