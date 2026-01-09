import BuildServerProtocol
import Foundation
import SWBProtocol
import SwiftBuild

extension BuildTargetIdentifier {
    private static let scheme = "xcode-bsp"

    init(configuredTargetIdentifier: SWBConfiguredTargetIdentifier) throws {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "configured-target"
        components.queryItems = [
            URLQueryItem(
                name: "targetGUID",
                value: configuredTargetIdentifier.targetGUID.rawValue.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                )
            ),
            URLQueryItem(
                name: "configuredTargetGUID",
                value: configuredTargetIdentifier.rawGUID.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                )
            ),
        ]

        guard let url = components.url else {
            throw BuildServerError.cannotCreateBuiltTargetIdentifier(from: configuredTargetIdentifier)
        }

        self.init(uri: URI(url))
    }

    var configuredTargetIdentifier: SWBConfiguredTargetIdentifier {
        get throws {
            guard let components = URLComponents(url: uri.arbitrarySchemeURL, resolvingAgainstBaseURL: false) else {
                throw BuildServerError.invalidTargetIdentifier(uri.arbitrarySchemeURL)
            }

            guard components.scheme == Self.scheme, components.host == "configured-target" else {
                throw BuildServerError.invalidTargetIdentifier(uri.arbitrarySchemeURL)
            }

            let targetGUID = components.queryItems?
                .last { $0.name == "targetGUID" }?
                .value?
                .removingPercentEncoding

            let configuredTargetGUID = components.queryItems?
                .last { $0.name == "configuredTargetGUID" }?
                .value?
                .removingPercentEncoding

            guard let configuredTargetGUID, let targetGUID else {
                throw BuildServerError.invalidTargetIdentifier(uri.arbitrarySchemeURL)
            }

            return SWBConfiguredTargetIdentifier(
                rawGUID: configuredTargetGUID,
                targetGUID: SWBTargetGUID(rawValue: targetGUID)
            )
        }
    }
}
