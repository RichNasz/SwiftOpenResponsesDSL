// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "SwiftOpenResponsesDSL",
	platforms: [
		.macOS(.v13),
		.iOS(.v16),
	],
	products: [
		.library(
			name: "SwiftOpenResponsesDSL",
			targets: ["SwiftOpenResponsesDSL"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/RichNasz/SwiftChatCompletionsMacros.git", from: "0.1.1"),
	],
	targets: [
		.target(
			name: "SwiftOpenResponsesDSL",
			dependencies: [
				.product(name: "SwiftChatCompletionsMacros", package: "SwiftChatCompletionsMacros"),
			]
		),
		.testTarget(
			name: "SwiftOpenResponsesDSLTests",
			dependencies: ["SwiftOpenResponsesDSL"]
		),
	]
)
