import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import Logging
import SwiftBuild

// nonisolated(unsafe) var logger = Logger()

nonisolated(unsafe) var logger = Logger(label: "xcode-bsp")

//@main
//class App {
//    static func main() async throws {
////        try await Task {
//            let indexer = try await Indexer()
//            await indexer.run()
////        }.value
//
////        while true {
////            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
////            logger.info("10 year wait that's parking the main thread expired. Waiting again.")
////        }
//    }
//}
//
//class Indexer: SWBIndexingDelegate {
//    let session: SWBBuildServiceSession
//
//    deinit {
//        print("Indexer.deinit()")
//    }
//
//    init() async throws {
//        let service = try await SWBBuildService(
//            connectionMode: .default,
//            variant: .default,
////            serviceBundleURL: aap
//        )
//
//        self.session = try await service.createSession(
//            name: "/Users/ward/Desktop/KLAATU/cache/workspace",
//            developerPath: "/Applications/Xcode.app/Contents/Developer",
//            cachePath: "/Users/ward/Desktop/KLAATU/cache",
//            inferiorProductsPath: "/Users/ward/Desktop/KLAATU/inferiorProducts",
//            environment: [:]
//        ).0.get()
//
//    }
//
//    func run() async {
//        do {
//            try await self.session.loadWorkspace(containerPath: "/Users/ward/Desktop/Routertje/Routertje.xcodeproj")
//
//            let workspaceInfo = try await session.workspaceInfo()
//            let target = workspaceInfo.targetInfos.first { $0.targetName == "Routertje" }!
//
//            var request = SWBBuildRequest()
////            request.buildCommand = .prepareForIndexing(buildOnlyTheseTargets: nil, enableIndexBuildArena: true)
////            request.buildCommand = .buildFiles(
////                paths: ["/Users/ward/Desktop/Routertje/Routertje/ContentView.swift"],
////                action: .compile
////            )
//
//            request.buildCommand = .build(style: .buildOnly)
//
//            request.enableIndexBuildArena = true
//            request.parameters.arenaInfo = SWBArenaInfo(
//                derivedDataPath: "/Users/ward/Desktop/KLAATU/arena/derivedData",
//                buildProductsPath: "/Users/ward/Desktop/KLAATU/arena/buildProducts",
//                buildIntermediatesPath: "/Users/ward/Desktop/KLAATU/arena/buildIntermediates",
//                pchPath: "/Users/ward/Desktop/KLAATU/arena/pch",
//                indexRegularBuildProductsPath: "/Users/ward/Desktop/KLAATU/arena/indexRegularBuildProducts",
//                indexRegularBuildIntermediatesPath: "/Users/ward/Desktop/KLAATU/arena/indexRegularBuildIntermediates",
//                indexPCHPath: "/Users/ward/Desktop/KLAATU/arena/indexPCH",
//                indexDataStoreFolderPath: "/Users/ward/Desktop/KLAATU/arena/indexDataStoreFolder",
//                indexEnableDataStore: true
//            )
////            request.parameters = SWBBuildParameters()
//            request.parameters.action = "build"
//            request.parameters.configurationName = "Debug"
////            request.parameters.activeRunDestination = SWBRunDestinationInfo(
////                platform: "iphonesimulator",
////                sdk: "iphonesimulator26.1",
////                sdkVariant: nil,
////                targetArchitecture: "arm64",
////                supportedArchitectures: [],
////                disableOnlyActiveArch: false,
////                hostTargetedPlatform: nil
////            )
////
//            request.add(target: SWBConfiguredTarget(guid: target.guid))
//
//            let buildOperation = try await session.createBuildOperation(request: request, delegate: self)
//            let events = try await buildOperation.start()
//
////            for await event in events {
////                print(event)
////            }
//
//            await buildOperation.waitForCompletion()
//
//            print("done")
//
//            //        let data = try req.jsonData()
//            //        print(String(data: data, encoding: .utf8))
//
////            let settings = try await session.generateIndexingFileSettings(
////                for: request,
////                targetID: target.guid,
////                filePath: "/Users/ward/Desktop/Routertje/Routertje/ContentView.swift",
////                outputPathOnly: false,
////                delegate: self
////            )
////
////            print(settings.sourceFileBuildInfos)
//
//            try await session.close()
//        } catch let error {
//            print(error)
//            try! await session.close()
//        }
//    }
//
//    func provisioningTaskInputs(
//        targetGUID: String,
//        provisioningSourceData: SWBProvisioningTaskInputsSourceData
//    ) async -> SWBProvisioningTaskInputs {
//        print("provisioningTaskInputs?")
//        return SWBProvisioningTaskInputs()
//    }
//
//    func executeExternalTool(
//        commandLine: [String],
//        workingDirectory: String?,
//        environment: [String : String]
//    ) async throws -> SWBExternalToolResult {
////        print("executeExternalTool", commandLine, workingDirectory)
//        return .deferred
//        //        let output = try await Command.run(
//        //            arguments: commandLine,
//        //            workingDirectory: workingDirectory.map { try AbsolutePath(validating: $0) }
//        //        )
//        //
//        //        return SWBExternalToolResult(
//    }
//}

@main
struct CLI: AsyncParsableCommand {
    @MainActor static var projectFileName: String!
    @Option var project: String

    @MainActor
    func run() async throws {
        let pwd = FileManager.default.currentDirectoryPath

        LoggingSystem.bootstrap { _ in
            FileLogHandler(fileURL: URL(filePath: "\(pwd)/.xcodebsp/output.log"))
            // MultiplexLogHandler([
            //     FileLogHandler(fileURL: URL(filePath: "/Users/ward/Desktop/xcodebsp-output.log")!)
            // ])
        }

        Self.projectFileName = project  // "Routertje.xcodeproj"

        logger.info("")
        logger.info("---------------------------")
        logger.info("Starting Xcode Build Server")
        logger.info("directory: \(pwd)")
        logger.info("project:   \(project)")
        logger.info("---------------------------")

        Task {
            BuildServer().start()
        }

        //        let session = try await service.createSession(
        //            name: "/Users/ward/Desktop/KLAATU/cache/workspace",
        //            developerPath: "/Applications/Xcode.app/Contents/Developer",
        //            cachePath: "/Users/ward/Desktop/KLAATU/cache",
        //            inferiorProductsPath: "/Users/ward/Desktop/KLAATU/inferiorProducts",
        //            environment: [:]
        //        ).0.get()
        //
        //        let connection = JSONRPCConnection(
        //            name: "XcodeBSP",
        //            protocol: .bspProtocol,
        //            inFD: FileHandle.standardInput,
        //            outFD: FileHandle.standardOutput,
        //            inputMirrorFile: nil,
        //            outputMirrorFile: nil
        //        )

        //        Task {
        //            SWBBuildServer(
        //                session: session,
        //                containerPath: <#T##String#>,
        //                buildRequest: <#T##_#>,
        //                connectionToClient: connection
        //            ) { status in
        //                exit(status)
        //            }
        //        }

        // Park the main function by sleeping for 10 years.
        // All request handling is done on other threads and sourcekit-lsp exits by calling `_Exit` when it receives a
        // shutdown notification.
        while true {
            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
            //            logger.info("10 year wait that's parking the main thread expired. Waiting again.")
        }

        //        logger.info("Exiting!")
    }
}
