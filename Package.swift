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
        .package(url: "https://github.com/tuist/FileSystem", from: "0.13.47"),
        .package(url: "https://github.com/Ryu0118/ProcessRunning", from: "0.2.1"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.0"),
        .package(url: "https://github.com/mtj0928/swift-async-operations", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "egg",
            dependencies: [
                "EggCLI",
            ]
        ),
        .target(
            name: "EggCLI",
            dependencies: [
                "EggKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "FileSystem", package: "FileSystem"),
                .product(name: "ProcessRunning", package: "ProcessRunning"),
            ]
        ),
        .target(
            name: "EggKit",
            dependencies: [
                .product(name: "ProcessRunning", package: "ProcessRunning"),
                .product(name: "FileSystem", package: "FileSystem"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "AsyncOperations", package: "swift-async-operations"),
            ]
        ),
        .testTarget(
            name: "EggKitTests",
            dependencies: [
                "EggKit",
                .product(name: "Yams", package: "Yams"),
                .product(name: "FileSystemTesting", package: "FileSystem"),
            ],
            exclude: [
                "Fixtures",
            ]
        ),
        .target(name: "NetworkClient"),
        .testTarget(
            name: "NetworkClientTests",
            dependencies: [ "NetworkClient" ]
        ),
        .target(name: "TestModule"),
        .testTarget(
            name: "TestModuleTests",
            dependencies: [ "TestModule" ]
        ),
    ]
)
