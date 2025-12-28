import BuildServerProtocol
import SwiftBuild

extension BuildTargetIdentifier {
    var configuredTargetIdentifier: SWBConfiguredTargetIdentifier {
        let targetGuid = uri.stringValue.replacing("swbuild-target://", with: "")
        return SWBConfiguredTargetIdentifier(rawGUID: targetGuid, targetGUID: SWBTargetGUID(rawValue: targetGuid))
    }
}
