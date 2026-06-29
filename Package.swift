// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "egg",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "egg", targets: ["egg"]),
        .library(name: "EggKit", targets: ["EggKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/tuist/Noora", from: "0.51.2"),
        .package(url: "https://github.com/Ryu0118/FileManagerProtocol", from: "0.1.0"),
        .package(url: "https://github.com/Ryu0118/ProcessRunning", from: "0.2.1"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.0"),
        .package(url: "https://github.com/mtj0928/swift-async-operations", from: "0.4.0"),
        .package(url: "https://github.com/tuist/FileSystem", from: "0.13.47"),
        .package(url: "https://github.com/stencilproject/Stencil", from: "0.15.1"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "egg",
            dependencies: [
                "EggCLI",
            ],
        ),
        .target(
            name: "EggCLI",
            dependencies: [
                "EggKit",
                "EggMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
                .product(name: "ProcessRunning", package: "ProcessRunning"),
                .product(name: "AsyncOperations", package: "swift-async-operations"),
            ],
        ),
        .target(
            name: "EggKit",
            dependencies: [
                .product(name: "ProcessRunning", package: "ProcessRunning"),
                .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "Glob", package: "FileSystem"),
                .product(name: "AsyncOperations", package: "swift-async-operations"),
                .product(name: "Stencil", package: "Stencil"),
            ],
        ),
        .target(
            name: "EggMCP",
            dependencies: [
                "EggKit",
                .product(name: "MCP", package: "swift-sdk"),
            ],
        ),
        .testTarget(
            name: "EggKitTests",
            dependencies: [
                "EggKit",
                .product(name: "Yams", package: "Yams"),
                .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
            ],
            exclude: [
                "Fixtures",
            ],
        ),
        .testTarget(
            name: "EggMCPTests",
            dependencies: [
                "EggMCP",
                "EggKit",
            ],
        ),
    ],
)
