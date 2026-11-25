// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QinXu",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QinXuCore", targets: ["QinXuCore"]),
        .executable(name: "QinXuPreview", targets: ["QinXuApp"])
    ],
    targets: [
        .target(name: "QinXuCore"),
        .executableTarget(name: "QinXuApp", dependencies: ["QinXuCore"]),
        .testTarget(name: "QinXuCoreTests", dependencies: ["QinXuCore"]),
        .testTarget(name: "QinXuAppTests", dependencies: ["QinXuApp", "QinXuCore"])
    ],
    swiftLanguageModes: [.v5]
)
