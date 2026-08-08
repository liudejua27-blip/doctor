// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BodyCompanion",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BodyCompanionCore", targets: ["BodyCompanionCore"]),
        .library(name: "BodyCompanionIOS", targets: ["BodyCompanionIOS"]),
        .executable(name: "BodyCompanionPrototype", targets: ["BodyCompanionPrototype"]),
    ],
    targets: [
        .target(
            name: "BodyCompanionCore",
            path: "Sources/BodyCompanionCore"
        ),
        .target(
            name: "BodyCompanionIOS",
            dependencies: ["BodyCompanionCore"],
            path: "Sources/BodyCompanionIOS",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "BodyCompanionPrototype",
            dependencies: ["BodyCompanionIOS"],
            path: "Sources/BodyCompanionPrototype"
        ),
        .testTarget(
            name: "BodyCompanionCoreTests",
            dependencies: ["BodyCompanionCore"],
            path: "Tests/BodyCompanionCoreTests"
        ),
    ]
)
