// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "xcode-bsp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "xcodebsp", targets: ["XcodeBSP"])
        // .executable(name: "SWBBuildServiceBundle", targets: ["BuildServiceBundle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/swift-tools-protocols.git", from: "0.0.9"),
        .package(
            url: "https://github.com/swiftlang/swift-build.git",
            revision: "7737a7666ca94d191f33ce3d029f38d97196b50b"
        ),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/tuist/Path", from: "0.3.8"),
    ],
    targets: [
        .executableTarget(
            name: "XcodeBSP",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
                .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
                .product(name: "SwiftBuild", package: "swift-build"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Path", package: "path"),
                .product(name: "SWBBuildServiceBundle", package: "swift-build"),
            ]
        ),
        .executableTarget(
            name: "BuildServiceBundle",
            dependencies: [
                .product(name: "SWBBuildService", package: "swift-build")
            ]
        ),
    ]
)
