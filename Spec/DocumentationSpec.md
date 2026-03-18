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
