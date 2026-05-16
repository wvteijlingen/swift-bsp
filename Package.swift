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
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
        .package(url: "https://github.com/swiftlang/swift-tools-protocols.git", from: "0.0.10"),
        .package(
            url: "https://github.com/swiftlang/swift-build.git",
            revision: "fc3609a1658bc5e119dc38906eb8049a9e8b24a1"
        ),
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
        )
    ]
)
