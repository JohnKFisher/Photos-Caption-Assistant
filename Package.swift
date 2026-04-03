// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotosCaptionAssistant",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PhotosCaptionAssistant", targets: ["PhotosCaptionAssistant"])
    ],
    targets: [
        .executableTarget(
            name: "PhotosCaptionAssistant",
            path: "Sources/PhotosCaptionAssistant",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "PhotosCaptionAssistantTests",
            dependencies: ["PhotosCaptionAssistant"],
            path: "Tests/PhotosCaptionAssistantTests"
        )
    ]
)
