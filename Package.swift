// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "xcode-bsp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "xcodebsp", targets: ["XcodeBSP"])
        //        .executable(name: "SWBBuildServiceBundle", targets: ["SWBBuildServiceBundle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/swift-tools-protocols.git", from: "0.0.9"),
        .package(url: "https://github.com/tuist/Command.git", from: "0.13.0"),
        .package(url: "https://github.com/tuist/xcodeproj.git", from: "9.6.0"),
        .package(
            url: "https://github.com/swiftlang/swift-build.git",
            revision: "7737a7666ca94d191f33ce3d029f38d97196b50b"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "XcodeBSP",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
                .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
                .product(name: "Command", package: "Command"),
                .product(name: "XcodeProj", package: "XcodeProj"),
                //                .target(name: "SWBBuildServiceBundle"),
                .product(name: "SwiftBuild", package: "swift-build"),
                .product(name: "Logging", package: "swift-log"),
                //                .product(name: "SWBBuildServiceBundle", package: "swift-build"),
            ]
        )
        //        .executableTarget(
        //            name: "SWBBuildServiceBundle",
        //            dependencies: [
        //                .product(name: "SWBBuildService", package: "swift-build"),
        //                .product(name: "SWBBuildSystem", package: "swift-build"),
        //                .product(name: "SWBServiceCore", package: "swift-build"),
        //                .product(name: "SWBUtil", package: "swift-build"),
        //                .product(name: "SWBCore", package: "swift-build"),
        //            ]
        //        )
    ]
)
