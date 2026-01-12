// import ArgumentParser
// import Foundation
// import LanguageServerProtocolTransport
// // import Logging
// import SwiftBuild

// @main
// struct CLI: AsyncParsableCommand {
//     @Option var project: String
//     @Flag var persistLog = false

//     @MainActor
//     func run() async throws {
//         let pwd = FileManager.default.currentDirectoryPath
//         let projectFilePath = try AbsolutePath(validating: pwd).appending(component: project)
//         let logFileURL = URL(filePath: "\(pwd)/.xcode-bsp/xcode-bsp.log")

//         if !persistLog {
//             try? FileManager.default.removeItem(at: logFileURL)
//         }

//         let logger = Logger(fileURL: logFileURL)

//         logger.info("---------------------------")
//         logger.info("Starting Xcode Build Server")
//         logger.info("directory: \(pwd)")
//         logger.info("project:   \(project)")
//         logger.info("---------------------------")

//         // Task {
//         //     let buildService = try await SWBBuildService(connectionMode: .inProcess, variant: .default)
//         //     let (sessionResult, _) = await buildService.createSession(
//         //         name: projectFilePath.pathString,
//         //         developerPath: "/Applications/Xcode.app/Contents/Developer",
//         //         cachePath: nil,
//         //         inferiorProductsPath: nil,
//         //         environment: [:]
//         //     )

//         //     let session = try sessionResult.get()

//         //     var buildRequest = SWBBuildRequest()
//         //     let workspaceInfo = try await session.workspaceInfo()
//         //     for target in workspaceInfo.targetInfos {
//         //         buildRequest.add(target: SWBConfiguredTarget(guid: target.guid))
//         //     }

//         //     let connection = JSONRPCConnection(
//         //         name: "XcodeBSP",
//         //         protocol: .bspProtocol,
//         //         inFD: FileHandle.standardInput,
//         //         outFD: FileHandle.standardOutput,
//         //         inputMirrorFile: nil,
//         //         outputMirrorFile: nil
//         //     )

//         //     let buildServer = SWBBuildServer(
//         //         session: session,
//         //         containerPath: projectFilePath.pathString,
//         //         buildRequest: buildRequest,
//         //         connectionToClient: connection,
//         //         exitHandler: { @Sendable code in
//         //             logger.info("Exiting with code \(code)")
//         //             _Exit(Int32(code))
//         //         })

//         //     connection.start(
//         //         receiveHandler: buildServer,
//         //         closeHandler: {
//         //             //
//         //         }
//         //     )
//         // }

//         Task {
//             let buildServer = BuildServer(
//                 projectFilePath: projectFilePath,
//                 logger: logger,
//                 onExit: { @Sendable code in
//                     logger.info("Exiting with code \(code)")
//                     _Exit(code)
//                 })

//             await buildServer.start()
//         }

//         // Park the main function by sleeping for 10 years
//         while true {
//             try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
//         }

//         logger.info("Exiting!")
//     }
// }
