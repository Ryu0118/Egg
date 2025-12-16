// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "E2ETestsPackage",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/Ryu0118/ProcessRunning", from: "0.2.1"),
        .package(url: "https://github.com/Ryu0118/FileManagerProtocol", from: "0.1.0"),
    ],
    targets: [
        .testTarget(
            name: "E2ETests",
            dependencies: [
                .product(name: "ProcessRunning", package: "ProcessRunning"),
                .product(name: "FileManagerProtocol", package: "FileManagerProtocol"),
            ]
        ),
    ]
)
