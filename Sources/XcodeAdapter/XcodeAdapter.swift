import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import Subprocess
import System
import XcodeProj
import Shared

public actor XcodeAdapter {
    private let config: Shared.Configuration
    private let xcodeProj: XcodeProj
    private let taskReporter: TaskReporter
    private let logReporter: LogReporter
    private let diagnosticsReporter: DiagnosticsReporter

    public init(
        config: Shared.Configuration,
        taskReporter: TaskReporter,
        logReporter: LogReporter,
        diagnosticsReporter: DiagnosticsReporter
    ) throws {
        self.config = config
        self.xcodeProj = try XcodeProj(pathString: config.xcodeProjectPath.string)
        self.taskReporter = taskReporter
        self.logReporter = logReporter
        self.diagnosticsReporter = diagnosticsReporter
    }

    public func loadBuildTargets() async throws -> [BuildTarget] {
        try taskReporter.log(message: "Loading Xcode schemes") { _ in
            try xcodeProj.allSchemes.map { scheme in
                try BuildTarget(
                    id: BuildTargetIdentifier(xcodeScheme: scheme),
                    displayName: "Scheme: \(scheme.name)",
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
    }

    public func loadBuildTargetDestinations(
        target: BuildTargetIdentifier
    ) async throws -> BuildTargetDestinationsResponse {
        let target = try target.xcodeTarget

        return try await taskReporter.log(message: "Loading destinations for '\(target.schemeName)'") { _ in
            let result = try await succeedAndGetOutput(
                .name("xcodebuild"),
                ["-showdestinations", "-scheme", target.schemeName]
            )

            let destinations = try result.components(separatedBy: .newlines)
                .compactMap { line -> BuildTargetDestination? in
                    guard let destination = XcodeDestination(xcodebuildLine: line) else { return nil }

                    return BuildTargetDestination(
                        id: try BuildTargetDestinationIdentifier(xcodeDestination: destination),
                        displayName: destination.displayName
                    )
                }

            return BuildTargetDestinationsResponse(destinations: destinations)
        }
    }

    public func compile(
        target: BuildTargetIdentifier,
        destination: BuildTargetDestinationIdentifier
    ) async throws -> BuildTargetCompileResponse {
        let productPath = try await build(target: target, destination: destination)

        return BuildTargetCompileResponse(
            statusCode: .ok,
            dataKind: .artifacts,
            data: .dictionary([
                "artifacts": .array([
                    .string(productPath.string)
                ])
            ])
        )
    }

    public func run(target: BuildTargetIdentifier, destination: BuildTargetDestinationIdentifier) async throws {
        let appBundlePath = try await build(target: target, destination: destination)
        let bundleID = "com.example.apple-samplecode.Scrumdinger" // TODO
        let simulator = try SimulatorController(udid: destination.id)

        try await taskReporter.log(message: "Installing app bundle '\(appBundlePath)'") { _ in
            try await simulator.open()
            try await simulator.install(appBundleAtPath: appBundlePath)
        }

        try await taskReporter.log(message: "Launching app bundle '\(bundleID)'") { _ in
            try await simulator.launchProcess(bundleID: bundleID)
        }
    }

    public func test(targets: [BuildTargetIdentifier]) async throws {
        // TODO: Implement
    }

    private func build(
        target: BuildTargetIdentifier,
        destination: BuildTargetDestinationIdentifier
    ) async throws -> FilePath {
        let xcodeTarget = try target.xcodeTarget

        diagnosticsReporter.clearAll(buildTarget: target)

        return try await taskReporter.log(
            message: "Building scheme '\(xcodeTarget.schemeName)'",
            data: CompileTaskData(target: target)
        ) { _ in
            let osaPath = Bundle.module.path(forResource: "osa", ofType: "js").map { FilePath($0) }!

            chmod(osaPath.string, 0o700)

            let scheme = xcodeProj.allSchemes.first { $0.name == xcodeTarget.schemeName }!

            _ = try await Subprocess.run(
                .path(osaPath),
                arguments: [config.xcodeProjectPath.removingLastComponent().string, scheme.name, destination.id],
                input: .none,
                output: .sequence,
                error: .sequence
            ) { execution in
                try await handleOutputStream(execution.standardOutput, scheme: scheme)
            }

            return try await getBuildPath(schemeName: xcodeTarget.schemeName, destinationID: destination.id)
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

        guard let builtProductsDir = target.buildSettings["BUILT_PRODUCTS_DIR"],  // /Users/.../Products/Debug-iphoneos
              let fullProductName = target.buildSettings["FULL_PRODUCT_NAME"] // Product.app
                // let executablePath = target.buildSettings["EXECUTABLE_PATH"]  // Product.app/Product
        else {
            throw BuildServerError.generic("Could not extract build path for '\(schemeName)'")
        }

        return FilePath(builtProductsDir).appending(fullProductName)
    }

    private func handleOutputStream(_ stream: SubprocessOutputSequence, scheme: XCScheme) async throws {
        let parser = XcodeOutputParser()
        // var didReset: Set<FilePath> = []

        for try await line in stream.strings() {
            let output = parser.handle(line: line)

            switch output {
            case .diagnostic(let file, let diagnostic):
                diagnosticsReporter.report(
                    [diagnostic],
                    textDocument: TextDocumentIdentifier(file.fileURI),
                    buildTarget: try BuildTargetIdentifier(xcodeScheme: scheme),
                    reset: false //!didReset.contains(file)
                )

                let logType: WindowMessageType =
                    switch diagnostic.severity {
                    case .error: .error
                    case .warning: .warning
                    case .information, .hint: .info
                    case nil: .info
                    }

                logReporter.log(message: line, type: logType)

                // didReset.insert(file)
            case .output:
                logReporter.log(message: line, type: .info)
            }
        }
    }
}

// MARK: - Models

private struct BuildTargetSettings: Decodable {
    let target: String
    let buildSettings: [String: String]
}

// MARK: - BSPAdapter

extension XcodeAdapter: BSPAdapter {
    public func handleOnWatchedFilesDidChange(
        notification: OnWatchedFilesDidChangeNotification
    ) async throws -> OnBuildTargetDidChangeNotification? {
        return nil
    }
    
    public func handleInitializeBuild(
        request: InitializeBuildRequest
    ) async throws -> (capabilities: BuildServerCapabilities, sourceKitData: LSPAny?) {
        let languageIds = [Language.swift, .c, .cpp, .objective_c, .objective_cpp]

        let capabilities = BuildServerCapabilities(
            compileProvider: CompileProvider(languageIds: languageIds),
            testProvider: TestProvider(languageIds: languageIds),
            runProvider: RunProvider(languageIds: languageIds),
            debugProvider: DebugProvider(languageIds: languageIds),
            inverseSourcesProvider: false,
            dependencySourcesProvider: false,
            resourcesProvider: false,
            outputPathsProvider: false,
            buildTargetChangedProvider: false,
            jvmRunEnvironmentProvider: false,
            jvmTestEnvironmentProvider: false,
            cargoFeaturesProvider: false,
            canReload: false,
            jvmCompileClasspathProvider: false
        )

        return (capabilities, nil)
    }
    
    public func handleBuildShutdown(
        request: BuildShutdownRequest
    ) async throws -> VoidResponse {
        VoidResponse()
    }
    
    public func handleBuildTargetSources(
        request: BuildTargetSourcesRequest
    ) async throws -> BuildTargetSourcesResponse {
        throw ResponseError.requestNotImplemented(BuildTargetSourcesRequest.self)
    }
    
    public func handleWorkspaceBuildTargets(
        request: WorkspaceBuildTargetsRequest
    ) async throws -> WorkspaceBuildTargetsResponse {
        try await WorkspaceBuildTargetsResponse(targets: loadBuildTargets())
    }
    
    public func handleWorkspaceWaitForBuildSystemUpdates(
        request: WorkspaceWaitForBuildSystemUpdatesRequest
    ) async throws -> VoidResponse {
        VoidResponse()
    }
    
    public func handleBuildTargetCompile(
        request: BuildTargetCompileRequest
    ) async throws -> BuildTargetCompileResponse {
        if request.targets.count > 1 {
            throw BuildServerError.generic("Cannot compile more than one target at a time")
        }

        guard let firstTarget = request.targets.first else {
            throw BuildServerError.generic("No target specified")
        }

        guard let destination = request.destination else {
            throw BuildServerError.generic("No destination specified")
        }
        
        return try await compile(target: firstTarget, destination: destination)
    }
    
    public func handleBuildTargetDestinations(
        request: BuildTargetDestinationsRequest
    ) async throws -> BuildTargetDestinationsResponse {
        guard try request.target.kind == .xcodeScheme else {
            throw BuildServerError.generic("Querying destinations for Swift Build targets is not supported")
        }

        return try await loadBuildTargetDestinations(target: request.target)
    }

    public func handleBuildTargetRun(
        request: BuildTargetRunRequest
    ) async throws -> BuildTargetRunResponse {
        guard let destination = request.destination else {
            throw BuildServerError.generic("No destination specified")
        }

        try await run(target: request.target, destination: destination)

        return BuildTargetRunResponse(statusCode: .ok)
    }
    
    public func handleBuildTargetPrepare(
        request: BuildTargetPrepareRequest
    ) async throws -> VoidResponse {
        VoidResponse()
    }
    
    public func handleTextDocumentSourceKitOptions(
        request: TextDocumentSourceKitOptionsRequest
    ) async throws -> TextDocumentSourceKitOptionsResponse {
        throw ResponseError.requestNotImplemented(TextDocumentSourceKitOptionsRequest.self)
    }
}
