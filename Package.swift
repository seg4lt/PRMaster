// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRMaster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PRMaster", targets: ["PRMaster"])
    ],
    targets: [
        .executableTarget(
            name: "PRMaster",
            path: "Sources/PRMaster",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
