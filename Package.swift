// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QinXu",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QinXuCore", targets: ["QinXuCore"]),
        .executable(name: "QinXuPreview", targets: ["QinXuApp"])
    ],
    dependencies: [
        .package(name: "swift-sheet-music", path: "Dependencies/SwiftSheetMusic")
    ],
    targets: [
        .target(name: "QinXuCore"),
        .executableTarget(
            name: "QinXuApp",
            dependencies: [
                "QinXuCore",
                .product(name: "SheetMusicCore", package: "swift-sheet-music"),
                .product(name: "SheetMusicPDF", package: "swift-sheet-music"),
                .product(name: "SheetMusicOMRModel", package: "swift-sheet-music")
            ],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "QinXuCoreTests", dependencies: ["QinXuCore"]),
        .testTarget(name: "QinXuAppTests", dependencies: ["QinXuApp", "QinXuCore"])
    ],
    swiftLanguageModes: [.v5]
)
