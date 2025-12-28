import BuildServerProtocol
import Command
import Foundation
import LanguageServerProtocol
import Path
import SwiftBuild
import XcodeProj

typealias AbsolutePath = Path.AbsolutePath

actor XcodeProject {
    var indexStorePath: AbsolutePath {
        try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
        //    Path($0).dirname.join("index-store").str
    }
    var indexDatabasePath: AbsolutePath {
        try! AbsolutePath(validating: arena.indexDataStoreFolderPath!)
    }

    private let projectRoot: AbsolutePath
    private let projectFilePath: AbsolutePath
    private let arena: SWBArenaInfo
    private let xcodeProj: XcodeProj
    private let logger: (BuildServerProtocol.MessageType, String, BuildServerProtocol.StructuredLogKind?) -> Void
    private let buildServiceSession: SWBBuildServiceSession
    private var buildRequest: SWBBuildRequest {
        get async throws {
            var request = SWBBuildRequest()
            request.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
            request.parameters.arenaInfo = arena
            request.enableIndexBuildArena = true

            let workspaceInfo = try await buildServiceSession.workspaceInfo()

            for target in workspaceInfo.targetInfos {
                request.add(target: SWBConfiguredTarget(guid: target.guid))
            }

            return request
        }
    }

    private var _buildDescriptionID: SWBBuildDescriptionID?
    private var buildDescriptionID: SWBBuildDescriptionID {
        get async throws {
            if let _buildDescriptionID { return _buildDescriptionID }
            self._buildDescriptionID = try await loadBuildDescriptionID()
            return _buildDescriptionID!
        }
    }

    init(
        projectRoot: AbsolutePath,
        projectFileName: String,
        logger: @escaping (BuildServerProtocol.MessageType, String, BuildServerProtocol.StructuredLogKind?) -> Void
    ) async throws {
        let xcodeBspFolder = projectRoot.appending(components: ".xcodebsp")
        let service = try await SWBBuildService(connectionMode: .default, variant: .default)

        self.projectRoot = projectRoot
        self.projectFilePath = projectRoot.appending(component: projectFileName)
        self.arena = SWBArenaInfo(root: xcodeBspFolder.appending(component: "arena"), indexEnableDataStore: true)
        self.xcodeProj = try XcodeProj(pathString: projectFilePath.pathString)
        self.logger = logger

        self.buildServiceSession = try await service.createSession(
            name: projectRoot.pathString,
            developerPath: "/Applications/Xcode.app/Contents/Developer",
            cachePath: xcodeBspFolder.appending(component: "cache").pathString,
            inferiorProductsPath: xcodeBspFolder.appending(component: "inferiorProducts").pathString,
            environment: [:]
        ).0.get()

        try await buildServiceSession.loadWorkspace(containerPath: projectFilePath.pathString)
        try await buildServiceSession.setSystemInfo(.default())
    }

    // MARK: - Loaders

    private func loadBuildDescriptionID() async throws -> SWBBuildDescriptionID {
        let buildDescriptionOperation = try await buildServiceSession.createBuildOperationForBuildDescriptionOnly(
            request: buildRequest,
            delegate: self
        )

        var buildDescriptionID: SWBBuildDescriptionID?

        for try await event in try await buildDescriptionOperation.start() {
            guard case .reportBuildDescription(let info) = event else {
                continue
            }

            buildDescriptionID = SWBBuildDescriptionID(info.buildDescriptionID)
        }

        guard let buildDescriptionID else {
            throw BuildServerError.cannotLoadBuildDescriptionID
        }

        return buildDescriptionID
    }

    func loadBuildTargets() async throws -> [BuildTarget] {
        let targets = try await buildServiceSession.configuredTargets(
            buildDescription: try await buildDescriptionID,
            buildRequest: buildRequest
        )

        logger(.info, String(describing: targets), nil)

        return try targets.map { targetInfo in
            //            let tags = try await buildServiceSession.evaluateMacroAsStringList(
            //                "BUILD_SERVER_PROTOCOL_TARGET_TAGS",
            //                level: .target(targetInfo.identifier.targetGUID.rawValue),
            //                buildParameters: buildRequest.parameters,
            //                overrides: nil
            //            ).filter {
            //                !$0.isEmpty
            //            }.map {
            //                BuildTargetTag(rawValue: $0)
            //            }

            let toolchain = targetInfo.toolchain.map { toolchain in
                DocumentURI(filePath: toolchain.pathString, isDirectory: true)
            }

            let uri = try URI(string: "swbuild-target://\(targetInfo.identifier.rawGUID)")

            let dependencies = try targetInfo.dependencies.map { dependency in
                let uri = try URI(string: "swbuild-target://\(dependency.targetGUID)")
                return BuildTargetIdentifier(uri: uri)
            }

            return BuildTarget(
                id: BuildTargetIdentifier(uri: uri),
                displayName: targetInfo.name,
                baseDirectory: nil,
                tags: [],
                capabilities: BuildTargetCapabilities(),
                languageIds: [.c, .cpp, .objective_c, .objective_cpp, .swift],
                dependencies: dependencies,
                dataKind: .sourceKit,
                data: SourceKitBuildTarget(toolchain: toolchain).encodeToLSPAny()
            )
        }
    }

    func loadBuildSources(targetIdentifiers: [BuildTargetIdentifier]) async throws -> [SourcesItem] {
        logger(.info, "XcodeProject.loadBuildSources: start...", nil)

        let configuredTargetIdentifiers = targetIdentifiers.map(\.configuredTargetIdentifier)

        let response = try await buildServiceSession.sources(
            of: configuredTargetIdentifiers,
            buildDescription: buildDescriptionID,
            buildRequest: buildRequest
        )

        return try response.compactMap { swbSourcesItem -> SourcesItem? in
            let sources = swbSourcesItem.sourceFiles.map { sourceFile in
                return SourceItem(
                    uri: DocumentURI(URL(filePath: sourceFile.path.pathString)),
                    kind: .file,
                    generated: false,
                    dataKind: .sourceKit,
                    data: SourceKitSourceItemData(
                        language: sourceFile.language.flatMap { Language($0) },
                        outputPath: sourceFile.indexOutputPath
                    ).encodeToLSPAny()
                )
            }

            let uri = try URI(string: "swbuild-target://\(swbSourcesItem.configuredTarget.targetGUID.rawValue)")

            return SourcesItem(
                target: BuildTargetIdentifier(uri: uri),
                sources: sources
            )
        }
    }

    //    func buildAllTargets() async throws {
    //        guard let scheme = xcodeProj.allSchemes.first else {
    //            throw BuildServerError.schemeNotFound
    //        }
    //
    //        let arguments = [
    //            "/usr/bin/xcrun",
    //            "xcodebuild",
    //            "-scheme", scheme.name,
    //            "-derivedDataPath", arena.derivedDataPath.pathString,
    //            "CODE_SIGN_IDENTITY=\"\"",
    //            "CODE_SIGNING_REQUIRED=NO"
    //        ]
    //
    //        logger.("Building Xcode Project: \(arguments)")
    //
    //        let output = try await Command.run(arguments: arguments, workingDirectory: projectRoot).concatenatedString()
    //
    //        logger.("Finished building: \(output)")
    //    }

    func loadCompilerArguments(file: AbsolutePath, targetIdentifier: BuildTargetIdentifier) async throws -> [String] {
        try await buildServiceSession.indexCompilerArguments(
            of: SwiftBuild.AbsolutePath(validating: file.pathString),
            in: targetIdentifier.configuredTargetIdentifier,
            buildDescription: buildDescriptionID,
            buildRequest: buildRequest
        )
    }

    // MARK: - Mutators

    func prepareTargets(targets: [BuildTargetIdentifier]) async throws {
        var request = try await buildRequest

        let targetGUIDs = targets.map {
            $0.configuredTargetIdentifier.targetGUID.rawValue
        }

        request.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: targetGUIDs, enableIndexBuildArena: true)

        let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)

        let events = try await buildOperation.start()
        await self.logEvents(events)
        await buildOperation.waitForCompletion()
    }

    func buildIndex() async throws {
        // TODO
    }

    func buildTarget(target: String) async throws {
        var request = try await buildRequest
        request.buildCommand = .build(style: .buildOnly)
        request.parameters.action = "build"
        request.parameters.configurationName = "Debug"

        request.add(target: SWBConfiguredTarget(guid: target))

        let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)
        let events = try await buildOperation.start()

        for await event in events {
            print(event)
        }

        await buildOperation.waitForCompletion()
    }

    func buildSources(paths: [AbsolutePath], target: String) async throws {
        var request = try await buildRequest
        request.buildCommand = .buildFiles(paths: paths.map(\.pathString), action: .compile)
        request.parameters.action = "build"
        request.parameters.configurationName = "Debug"
        //        request.parameters.activeRunDestination = SWBRunDestinationInfo(
        //            platform: "iphonesimulator",
        //            sdk: "iphonesimulator26.1",
        //            sdkVariant: nil,
        //            targetArchitecture: "arm64",
        //            supportedArchitectures: [],
        //            disableOnlyActiveArch: false,
        //            hostTargetedPlatform: nil
        //        )

        request.add(target: SWBConfiguredTarget(guid: target))

        let buildOperation = try await buildServiceSession.createBuildOperation(request: request, delegate: self)
        let events = try await buildOperation.start()
        for await event in events {
            print(event)
        }

        await buildOperation.waitForCompletion()

        print("done")

    }

    // func schemes() throws -> [BuildTarget] {
    //     logger(.info, "Getting schemes")

    //     return xcodeProj.allSchemes.map { scheme in
    //         logger(.info, "Found scheme '\(scheme.name)'")

    //         let capabilities = BuildTargetCapabilities(
    //             canCompile: scheme.buildAction != nil,
    //             canTest: scheme.testAction != nil,
    //             canRun: scheme.launchAction != nil,
    //             canDebug: scheme.launchAction != nil
    //         )

    //         return BuildTarget(
    //             id: BuildTargetIdentifier(uri: scheme.uri),
    //             displayName: scheme.name,
    //             baseDirectory: nil,
    //             tags: [],
    //             capabilities: capabilities,
    //             languageIds: [.swift],
    //             dependencies: [],
    //             dataKind: .sourceKit,
    //             data: nil
    //         )
    //     }
    // }

    // func sourceFiles(forScheme uri: URI) async throws -> [SourceItem] {
    //     logger(.info, "Getting source files for scheme '\(uri)'")

    //     let scheme = xcodeProj.allSchemes.first { $0.uri == uri }

    //     guard let buildAction = scheme?.buildAction else {
    //         throw BuildServerError.noTargetsFound
    //     }

    //     let targets = buildAction.buildActionEntries.flatMap { entry in
    //         xcodeProj.pbxproj.targets(named: entry.buildableReference.blueprintName)
    //     }

    //     guard !targets.isEmpty else {
    //         logger(.warning, "Zero targets found for scheme '\(uri)'")
    //         return []
    //     }

    //     logger(.info, "Found \(targets.count) target(s) for scheme '\(uri)'")

    //     return try targets.flatMap { target in
    //         let sourceFiles = try target.sourceFiles()
    //         logger(.info, "Found \(sourceFiles.count) source files for target '\(target.name)'")

    //         return try sourceFiles.map { fileElement in
    //             guard let path = try fileElement.fullPath(sourceRoot: projectRoot.pathString) else {
    //                 logger(.warning, "No path for file '\(fileElement.path, default: "???")'")
    //                 throw BuildServerError.unknown
    //             }

    //             return SourceItem(
    //                 uri: URI(filePath: path, isDirectory: false),
    //                 kind: .file,
    //                 generated: false
    //             )
    //         }
    //     }
    // }

    //    func sourceFiles(forTargetNamed target: String) async throws -> [SourceItem] {
    //        let xcodeProject = try XcodeProj(pathString: projectRoot)
    //        let eligibleTargets = xcodeProject.pbxproj.targets(named: target)
    //
    //        if eligibleTargets.isEmpty {
    //            logger.warning("Zero targets found with name \(target)")
    //            throw BuildServerError.noTargetsFound
    //        } else if eligibleTargets.count > 1 {
    //            logger.warning("More than one target found with name \(target). Using first target")
    //        }
    //
    //        return try eligibleTargets[0].sourceFiles().map { fileElement in
    //            guard let path = try fileElement.fullPath(sourceRoot: Path(projectRoot)) else {
    //                fatalError("No path")
    //            }
    //
    //            return path.url
    //        }
    //    }
}

// MARK: - SWBPlanningOperationDelegate, SWBIndexingDelegate

extension XcodeProject: SWBIndexingDelegate {
    func provisioningTaskInputs(
        targetGUID: String,
        provisioningSourceData: SWBProvisioningTaskInputsSourceData
    ) async -> SWBProvisioningTaskInputs {
        SWBProvisioningTaskInputs()
    }

    func executeExternalTool(
        commandLine: [String],
        workingDirectory: String?,
        environment: [String: String]
    ) async throws -> SWBExternalToolResult {
        .deferred
    }
}

extension XcodeProject {
    private func logEvents(_ events: AsyncStream<SwiftBuildMessage>) async {
        for try await event in events {
            switch event {
            case .planningOperationStarted(_):
                logger(.log, "Planning Build", .begin(.init(title: "Planning Build")))
            case .planningOperationCompleted(_):
                logger(.info, "Build Planning Complete", .end(.init()))
            case .buildStarted(_):
                logger(.log, "Building", .begin(.init(title: "Building")))
            case .buildDiagnostic(let info):
                logger(.log, info.message, .report(.init()))
            case .buildCompleted(let info):
                switch info.result {
                case .ok:
                    logger(.log, "Build Complete", .end(.init()))
                case .failed:
                    logger(.log, "Build Failed", .end(.init()))
                case .cancelled:
                    logger(.log, "Build Cancelled", .end(.init()))
                case .aborted:
                    logger(.log, "Build Aborted", .end(.init()))
                }
            case .preparationComplete(_):
                logger(.log, "Build Preparation Complete", .end(.init()))
            case .didUpdateProgress(_):
                break
            case .taskStarted(let info):
                logger(.log, info.executionDescription, .begin(.init(title: info.executionDescription)))
            case .taskDiagnostic(let info):
                logger(.log, info.message, .report(.init()))
            case .taskComplete(_):
                break
            case .targetDiagnostic(let info):
                logger(.log, info.message, .report(.init()))
            case .diagnostic(let info):
                logger(.log, info.message, .report(.init()))
            case .backtraceFrame, .reportPathMap, .reportBuildDescription, .preparedForIndex, .buildOutput,
                .targetStarted, .targetComplete, .targetOutput, .targetUpToDate, .taskUpToDate, .taskOutput, .output:
                break
            }
        }
    }
}
