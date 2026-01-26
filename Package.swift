// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-bsp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "swift-bsp", targets: ["SwiftBSP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/swift-tools-protocols.git", from: "0.0.9"),
        .package(
            url: "https://github.com/swiftlang/swift-build.git",
            revision: "d3acea2a54048e173bc42148c587e81f73c3ab78"
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftBSP",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
                .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
                .product(name: "SwiftBuild", package: "swift-build"),
                .product(name: "SWBBuildServiceBundle", package: "swift-build"),
            ]
        ),
    ]
)
