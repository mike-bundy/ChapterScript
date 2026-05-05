// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChapterScript",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .visionOS(.v1),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "ChapterScript", targets: ["ChapterScript"])
    ],
    targets: [
        .target(
            name: "ChapterScript",
            path: "Sources/ChapterScript"
        ),
        .testTarget(
            name: "ChapterScriptTests",
            dependencies: ["ChapterScript"],
            path: "Tests/ChapterScriptTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
