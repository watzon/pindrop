// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PindropShared",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "PindropCore", targets: ["PindropCore"]),
        .library(name: "PindropAI", targets: ["PindropAI"]),
        .library(name: "PindropData", targets: ["PindropData"]),
        .library(name: "PindropSpeech", targets: ["PindropSpeech"]),
        .library(name: "PindropMedia", targets: ["PindropMedia"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.4"),
    ],
    targets: [
        .target(
            name: "PindropCore"
        ),
        .target(
            name: "PindropAI",
            dependencies: ["PindropCore"]
        ),
        .target(
            name: "PindropData",
            dependencies: ["PindropCore"]
        ),
        .target(
            name: "PindropSpeech",
            dependencies: [
                "PindropCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .target(
            name: "PindropMedia",
            dependencies: [
                "PindropCore",
                "PindropData",
            ]
        ),
        .testTarget(
            name: "PindropCoreTests",
            dependencies: ["PindropCore"]
        ),
        .testTarget(
            name: "PindropAITests",
            dependencies: ["PindropAI"]
        ),
        .testTarget(
            name: "PindropDataTests",
            dependencies: ["PindropData"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "PindropSpeechTests",
            dependencies: ["PindropSpeech"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "PindropMediaTests",
            dependencies: ["PindropMedia", "PindropData", "PindropCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
