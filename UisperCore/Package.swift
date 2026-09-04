// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UisperCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "UisperCore", targets: ["UisperCore"])],
    targets: [
        .target(name: "UisperCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "UisperCoreTests", dependencies: ["UisperCore"]),
    ]
)
