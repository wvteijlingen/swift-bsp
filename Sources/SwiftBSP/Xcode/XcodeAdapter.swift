import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import SwiftBuild
import System
import ToolsProtocolsSwiftExtensions
import XcodeProj
import Subprocess

actor XcodeAdapter: Adapter {
    private let containerPath: FilePath
    private let xcodeProj: XcodeProj
    private var taskReporter: TaskReporter

    init(containerPath: FilePath) throws {
        self.containerPath = containerPath
        self.xcodeProj = try XcodeProj(pathString: containerPath.string)
        self.taskReporter = TaskReporter(connection: nil)
    }

    func setTaskReporter(_ taskReporter: TaskReporter) {
        self.taskReporter = taskReporter
    }

    func waitForUpdates() async {
        // no-op, not supported by the Xcode Adapter
    }

    func loadProject() async throws {
        // no-op, not supported by the Xcode Adapter
    }

    func initialize() -> LSPAny? {
        return nil
    }

    func closeSession() async throws {
        // no-op, not supported by the Xcode Adapter
    }

    func loadBuildSources(targetIdentifiers: [XcodeTargetIdentifier]) async throws -> [SourcesItem] {
        []// no-op, not supported by the Xcode Adapter
    }

    func loadCompilerArguments(file: FilePath, targetIdentifier: XcodeTargetIdentifier) async throws -> [String] {
        []// no-op, not supported by the Xcode Adapter
    }

    func prepareTargets(targets: [XcodeTargetIdentifier]) async throws {
        // no-op, not supported by the Xcode Adapter
    }

    func loadBuildTargets() async throws -> [BuildTarget] {
        try taskReporter.log(title: "Loading Xcode schemes") {
            try xcodeProj.allSchemes.map { scheme in
                try BuildTarget(
                    id: BuildTargetIdentifier(xcodeScheme: scheme),
                    displayName: scheme.name,
                    baseDirectory: nil,
                    tags: [],
                    capabilities: BuildTargetCapabilities(
                        canCompile: scheme.buildAction != nil,
                        canTest: scheme.testAction != nil,
                        canRun: scheme.launchAction != nil,
                        canDebug: scheme.launchAction != nil
                    ),
                    languageIds: [],
                    dependencies: [],
                    dataKind: nil,
                    data: nil
                )
            }
        }

        //        let result = try await Subprocess.run(
        //            .name("ls"),
        //            arguments: ["xcodebuild", "-list", "-json", "-project"],
        //            output: .string(limit: 4096)
        //        )
        //
        //        let standardOutputData = result.standardOutput!.data(using: .utf8)!
        //
        //        let root = try JSONDecoder().decode(Root.self, from: standardOutputData)
        //
        //        return root.project.schemes.map { schemeName in
        //            BuildTarget(
        //                id: <#T##BuildTargetIdentifier#>,
        //                displayName: schemeName,
        //                baseDirectory: nil,
        //                tags: [],
        //                capabilities: BuildTargetCapabilities(,
        //                languageIds: <#T##[Language]#>,
        //                dependencies: <#T##[BuildTargetIdentifier]#>,
        //                dataKind: <#T##BuildTargetDataKind?#>,
        //                data: <#T##LSPAny?#>
        //            )
        //        }
    }

    func loadBuildTargetDestinations(targetIdentifier: XcodeTargetIdentifier) async throws -> [BuildTargetDestination] {
        try await taskReporter.log(title: "Loading destinations for '\(targetIdentifier.schemeName)'") {
            let result = try await succeedAndGetOutput(
                .name("xcodebuild"),
                ["-showdestinations", "-scheme", targetIdentifier.schemeName]
            )

            return try result.components(separatedBy: .newlines).compactMap { line -> BuildTargetDestination? in
                guard let destination = XcodeDestination(xcodebuildLine: line) else { return nil }

                return try BuildTargetDestination(
                    id: BuildTargetDestinationIdentifier(xcodeDestination: destination),
                    displayName: destination.displayName
                )
            }
        }
    }

    func compile(
        targetIdentifier: XcodeTargetIdentifier,
        destination: BuildTargetDestinationIdentifier?
    ) async throws -> BuildTargetCompileResponse {
        let productPath = try await build(targetIdentifier: targetIdentifier, destination: destination)

        return BuildTargetCompileResponse(
            statusCode: .ok,
            dataKind: .productPaths,
            data: LSPAny.dictionary([
                "productPaths": .array([
                    .string(productPath.string)
                ])
            ])
        )
    }

    func run(targetIdentifier: XcodeTargetIdentifier, destination: BuildTargetDestinationIdentifier) async throws {
        let appPath = try await build(targetIdentifier: targetIdentifier, destination: destination)

        
        try await Simulator.open(udid: destination.id)
        try await Simulator.install(appPath: appPath, deviceUdid: destination.id)
    }

    func test(targetIdentifiers: [XcodeTargetIdentifier]) async throws {
        // TODO: Implement
    }

    private func build(
        targetIdentifier: XcodeTargetIdentifier,
        destination: BuildTargetDestinationIdentifier?
    ) async throws -> FilePath {
        try await taskReporter.log(title: "Building \(targetIdentifier.schemeName)") {
            let osaPath = Bundle.module.path(forResource: "osa", ofType: "js").map {
                FilePath($0)
            }!

            chmod(osaPath.string, 0o700)

            let scheme = xcodeProj.allSchemes.first { $0.name == targetIdentifier.schemeName }!

            let destinationID = if let destination {
                destination.id
            } else {
                try await loadBuildTargetDestinations(targetIdentifier: targetIdentifier).first!.id.id
            }

            _ = try await Subprocess.run(
                .path(osaPath),
                arguments: [containerPath.removingLastComponent().string, scheme.name, destinationID],
                input: .none,
                output: .sequence,
                error: .sequence
            ) { execution in
                for try await line in execution.standardOutput.strings() {
                    print(line)
                }
            }

            return try await getBuildPath(schemeName: targetIdentifier.schemeName, destinationID: destinationID)
        }
    }

    private func getBuildPath(
        schemeName: String,
        destinationID: String
    ) async throws -> FilePath {
        let result = try await succeedAndGetOutput(
            .name("xcodebuild"),
            ["-showBuildSettings", "-json", "-scheme", schemeName, "-destination", "id=\(destinationID)"]
        )
        let data = result.data(using: .utf8)!
        let settings = try JSONDecoder().decode([BuildTargetSettings].self, from: data)

        guard let target = settings.first else {
            throw BuildServerError.generic("No build settings found for '\(schemeName)'")
        }

        guard let builtProductsDir = target.buildSettings["BUILT_PRODUCTS_DIR"], // /Users/.../Products/Debug-iphoneos
              // let fullProductName = target.buildSettings["FULL_PRODUCT_NAME"], // Product.app
              let executablePath = target.buildSettings["EXECUTABLE_PATH"] // Product.app/Product
        else {
            throw BuildServerError.generic("Could not extract build path for '\(schemeName)'")
        }

        return FilePath(builtProductsDir).appending(executablePath)
    }
}

private struct BuildTargetSettings: Decodable {
    let target: String
    let buildSettings: [String: String]
}
