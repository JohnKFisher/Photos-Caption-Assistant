// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoDescriptionCreator",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PhotoDescriptionCreator", targets: ["PhotoDescriptionCreator"])
    ],
    targets: [
        .executableTarget(
            name: "PhotoDescriptionCreator",
            path: "Sources/PhotoDescriptionCreator",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "PhotoDescriptionCreatorTests",
            dependencies: ["PhotoDescriptionCreator"],
            path: "Tests/PhotoDescriptionCreatorTests"
        )
    ]
)
