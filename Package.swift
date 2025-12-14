// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRReviewManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PRReviewManager", targets: ["PRReviewManager"])
    ],
    targets: [
        .executableTarget(
            name: "PRReviewManager",
            path: "Sources/PRReviewManager",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
