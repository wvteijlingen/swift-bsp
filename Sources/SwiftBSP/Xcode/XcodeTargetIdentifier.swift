import BuildServerProtocol
import SwiftBuild
import Foundation

struct XcodeTargetIdentifier  {
    let schemeName: String
//    let uri: URI
}

//extension SwiftBuildAdapter {
//    struct Target {
//        let targetGUID: SWBTargetGUID
//        let configuredTargetGUID: String
//
//        var asBuildTargetIdentifier: BuildTargetIdentifier {
//            var components = URLComponents()
//            components.scheme = Self.scheme
//            
//            components.host = "swift-build-configured-target"
//            components.queryItems = [
//                URLQueryItem(
//                    name: "targetGUID",
//                    value: configuredTargetIdentifier.targetGUID.rawValue.addingPercentEncoding(
//                        withAllowedCharacters: .urlQueryAllowed
//                    )
//                ),
//                URLQueryItem(
//                    name: "configuredTargetGUID",
//                    value: configuredTargetIdentifier.rawGUID.addingPercentEncoding(
//                        withAllowedCharacters: .urlQueryAllowed
//                    )
//                ),
//            ]
//
//            guard let url = components.url else {
//                throw BuildServerError.cannotCreateBuildTargetIdentifier(from: configuredTargetIdentifier)
//            }
//
//            self.init(uri: URI(url))
//        }
//    }
//}
