// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "macusagerep",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacUsageRepCore", targets: ["MacUsageRepCore"]),
        .executable(name: "macusagerep-agent", targets: ["MacUsageRepAgent"]),
        .executable(name: "macusagerep", targets: ["MacUsageRepApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "MacUsageRepCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/MacUsageRepCore"
        ),
        .executableTarget(
            name: "MacUsageRepAgent",
            dependencies: ["MacUsageRepCore"],
            path: "Sources/MacUsageRepAgent"
        ),
        .executableTarget(
            name: "MacUsageRepApp",
            dependencies: ["MacUsageRepCore"],
            path: "Sources/MacUsageRepApp"
        ),
        .testTarget(
            name: "MacUsageRepCoreTests",
            dependencies: ["MacUsageRepCore"],
            path: "Tests/MacUsageRepCoreTests"
        ),
    ]
)
