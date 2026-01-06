import BuildServerProtocol
import Foundation
import SWBProtocol
import SwiftBuild

extension BuildTargetIdentifier {
    private static let scheme = "swift-build"

    init(configuredTargetIdentifier: SWBConfiguredTargetIdentifier) throws {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "configured-target"
        components.queryItems = [
            URLQueryItem(name: "rawGUID", value: configuredTargetIdentifier.rawGUID),
            URLQueryItem(name: "targetGUID", value: configuredTargetIdentifier.targetGUID.rawValue),
        ]

        guard let url = components.url else {
            throw FailedToConvertSwiftBuildTargetToUrlError(configuredTargetIdentifier: configuredTargetIdentifier)
        }

        self.init(uri: URI(url))
    }

    var configuredTargetIdentifier: SWBConfiguredTargetIdentifier {
        get throws {
            guard
                let components = URLComponents(
                    url: self.uri.arbitrarySchemeURL,
                    resolvingAgainstBaseURL: false
                )
            else {
                throw InvalidTargetIdentifierError(target: self)
            }

            let rawGUID = components.queryItems?.last { $0.name == "rawGUID" }?.value
            let targetGUID = components.queryItems?.last { $0.name == "targetGUID" }?.value

            guard let rawGUID, let targetGUID else {
                throw InvalidTargetIdentifierError(target: self)
            }

            return SWBConfiguredTargetIdentifier(
                rawGUID: rawGUID,
                targetGUID: SWBTargetGUID(rawValue: targetGUID)
            )
        }
    }
}
