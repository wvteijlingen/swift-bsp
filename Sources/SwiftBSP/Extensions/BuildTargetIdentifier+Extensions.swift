import BuildServerProtocol
import Foundation
import SWBProtocol
import SwiftBuild

extension BuildTargetIdentifier {
    private static let scheme = "swift-bsp"

    init(configuredTargetIdentifier: SWBConfiguredTargetIdentifier, name: String?) throws {
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

        if let name {
            components.queryItems?.append(
                URLQueryItem(
                    name: "name",
                    value: name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                )
            )
        }

        guard let url = components.url else {
            throw BuildServerError.cannotCreateBuildTargetIdentifier(from: configuredTargetIdentifier)
        }

        self.init(uri: URI(url))
    }

    var configuredTargetGUID: String {
        get throws {
            try configuredTargetIdentifier.rawGUID
        }
    }

    var targetGUID: SWBTargetGUID {
        get throws {
            try configuredTargetIdentifier.targetGUID
        }
    }

    var targetName: String? {
        get throws {
            try value(for: "name", in: components)
        }
    }

    var configuredTargetIdentifier: SWBConfiguredTargetIdentifier {
        get throws {
            let components = try self.components
            let targetGUID = value(for: "targetGUID", in: components)
            let configuredTargetGUID = value(for: "configuredTargetGUID", in: components)

            guard let targetGUID, let configuredTargetGUID else {
                throw BuildServerError.invalidTargetIdentifier(components.url?.absoluteString ?? "<")
            }

            return SWBConfiguredTargetIdentifier(
                rawGUID: configuredTargetGUID,
                targetGUID: SWBTargetGUID(rawValue: targetGUID)
            )
        }
    }

    private var components: URLComponents {
        get throws {
            guard let components = URLComponents(url: uri.arbitrarySchemeURL, resolvingAgainstBaseURL: false) else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            guard components.scheme == Self.scheme, components.host == "configured-target" else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            return components
        }
    }
}

private func value(for queryItemName: String, in components: URLComponents) -> String? {
    let value = components.queryItems?
        .last { $0.name == queryItemName }?
        .value?
        .removingPercentEncoding

    return value
}