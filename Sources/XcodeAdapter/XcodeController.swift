// import Foundation
// import Subprocess
// import System
// import Shared

// enum XcodeController {
//     static func loadBuildTargetDestinations(
//         scheme: String
//     ) async throws -> [XcodeDestination] {
//         let result = try await succeedAndGetOutput(
//             .name("xcodebuild"),
//             ["-showdestinations", "-scheme", scheme]
//         )

//         return result
//             .components(separatedBy: .newlines)
//             .compactMap { line in
//                 XcodeDestination(xcodebuildLine: line)
//             }
//     }

//     static func getBuildPath(
//         scheme: String,
//         destinationID: String
//     ) async throws -> FilePath {
//         let result = try await succeedAndGetOutput(
//             .name("xcodebuild"),
//             ["-showBuildSettings", "-json", "-scheme", scheme, "-destination", "id=\(destinationID)"]
//         )

//         let data = result.data(using: .utf8)!
//         let settings = try JSONDecoder().decode([BuildTargetSettings].self, from: data)

//         guard let target = settings.first else {
//             throw BuildServerError.generic("No build settings found for '\(scheme)'")
//         }

//         guard let builtProductsDir = target.buildSettings["BUILT_PRODUCTS_DIR"],  // /Users/.../Products/Debug-iphoneos
//             // let fullProductName = target.buildSettings["FULL_PRODUCT_NAME"], // Product.app
//             let executablePath = target.buildSettings["EXECUTABLE_PATH"]  // Product.app/Product
//         else {
//             throw BuildServerError.generic("Could not extract build path for '\(scheme)'")
//         }

//         return FilePath(builtProductsDir).appending(executablePath)
//     }
// }

// private struct BuildTargetSettings: Decodable {
//     let target: String
//     let buildSettings: [String: String]
// }

// // extension XcodeController {
// //     struct Destination {
// //         let platform: String
// //         let arch: String
// //         let id: String
// //         let os: String
// //         let name: String

// //         var displayName: String {
// //             "\(platform) - \(name) (\(os))"
// //         }

// //         init?(xcodebuildLine line: String) {
// //             // Remove surrounding braces
// //             let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "{} \t").union(.whitespaces))

// //             var result: [String: String] = [:]

// //             // Split into key/value pairs
// //             let pairs = trimmed.split(separator: ",")

// //             for pair in pairs {
// //                 let parts = pair.split(separator: ":", maxSplits: 1)

// //                 guard parts.count == 2 else { continue }

// //                 let key = parts[0].trimmingCharacters(in: .whitespaces)
// //                 let value = parts[1].trimmingCharacters(in: .whitespaces)

// //                 result[key] = value
// //             }

// //             if result["error"] != nil {
// //                 // Most likely an ineligible destination
// //                 return nil
// //             }

// //             guard let platform = result["platform"],
// //                 let arch = result["arch"],
// //                 let id = result["id"],
// //                 let os = result["OS"],
// //                 let name = result["name"]
// //             else {
// //                 return nil
// //             }

// //             self.platform = platform
// //             self.arch = arch
// //             self.id = id
// //             self.os = os
// //             self.name = name
// //         }
// //     }
// // }
