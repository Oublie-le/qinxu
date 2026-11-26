// swift-tools-version: 6.2
import PackageDescription

// The PDF/OMR dependency graph of the pinned Swift Sheet Music revision.
// scripts/fetch-sheet-music.py installs the original sources and resources.
let package = Package(
    name: "swift-sheet-music",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SheetMusicCore", targets: ["SheetMusicCore"]),
        .library(name: "SheetMusicPDF", targets: ["SheetMusicPDF"]),
        .library(name: "SheetMusicOMRModel", targets: ["SheetMusicOMRModel"])
    ],
    targets: [
        .target(name: "SheetMusicFoundation"),
        .target(name: "SheetMusicCore", dependencies: ["SheetMusicFoundation"]),
        .target(name: "SheetMusicZip", dependencies: ["SheetMusicFoundation"]),
        .target(name: "SheetMusicPDFSyntax", dependencies: ["SheetMusicFoundation", "SheetMusicZip"]),
        .target(name: "SheetMusicLayout", dependencies: ["SheetMusicCore", "SheetMusicFoundation"]),
        .target(
            name: "SheetMusicLayoutApple",
            dependencies: ["SheetMusicCore", "SheetMusicLayout"],
            resources: [.process("Fonts/Resources")]
        ),
        .target(name: "SheetMusicUI", dependencies: ["SheetMusicCore", "SheetMusicLayout", "SheetMusicLayoutApple"]),
        .target(
            name: "SheetMusicPDF",
            dependencies: ["SheetMusicCore", "SheetMusicLayout", "SheetMusicLayoutApple", "SheetMusicPDFSyntax", "SheetMusicUI"]
        ),
        .target(
            name: "SheetMusicOMRModel",
            dependencies: ["SheetMusicPDF", "SheetMusicCore"],
            resources: [.copy("Resources/model.mlmodelc"), .copy("Resources/model.json")]
        )
    ]
)
