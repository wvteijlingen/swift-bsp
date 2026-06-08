import BuildServerProtocol
import Foundation
import SWBProtocol
import SwiftBuild
import XcodeProj

extension BuildTargetIdentifier {
    private static let scheme = "swift-bsp"

    init(configuredTargetIdentifier: SWBConfiguredTargetIdentifier) throws {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "swift-build-configured-target"
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
            throw BuildServerError.cannotCreateBuildTargetIdentifier(from: configuredTargetIdentifier.rawGUID)
        }

        self.init(uri: URI(url))
    }

    init(xcodeScheme: XCScheme) throws {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "xcode-scheme"
        components.queryItems = [
            URLQueryItem(
                name: "name",
                value: xcodeScheme.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            )
        ]

        guard let url = components.url else {
            throw BuildServerError.cannotCreateBuildTargetIdentifier(from: xcodeScheme.name)
        }

        self.init(uri: URI(url))
    }


    var xcodeTarget: XcodeTargetIdentifier? {
        get throws {
            let components = try components

            guard components.host == "xcode-scheme" else { return nil }

            let schemeName = components.queryItems?
                .last { $0.name == "name" }?
                .value?
                .removingPercentEncoding

            guard let schemeName else {
                throw BuildServerError.invalidTargetIdentifier(uri.arbitrarySchemeURL)
            }

            return XcodeTargetIdentifier(schemeName: schemeName)
        }
    }

    var swiftBuildTarget: SWBConfiguredTargetIdentifier? {
        get throws {
            let components = try components

            guard components.host == "swift-build-configured-target" else { return nil }

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

    private var components: URLComponents {
        get throws {
            guard let components = URLComponents(url: uri.arbitrarySchemeURL, resolvingAgainstBaseURL: false) else {
                throw BuildServerError.invalidTargetIdentifier(uri.arbitrarySchemeURL)
            }

            guard components.scheme == Self.scheme else {
                throw BuildServerError.invalidTargetIdentifier(uri.arbitrarySchemeURL)
            }

            return components
        }
    }
}
