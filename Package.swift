// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PianoPractice",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"]),
        .executable(name: "PianoPractice", targets: ["PianoApp"])
    ],
    targets: [
        .target(name: "PianoCore"),
        .executableTarget(name: "PianoApp", dependencies: ["PianoCore"]),
        .testTarget(name: "PianoCoreTests", dependencies: ["PianoCore"])
    ],
    swiftLanguageModes: [.v5]
)
