// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClawdDeck",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/appstefan/HighlightSwift", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ClawdDeck",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "HighlightSwift", package: "HighlightSwift")
            ],
            path: "Sources/ClawdDeck",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
