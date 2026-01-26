import Foundation
import SwiftBuild
import RegexBuilder

extension SWBConfiguredTargetIdentifier {
    var sdkVariant: String? {

        let variantRef = Reference<Substring>()

        let regex = Regex {
            Anchor.startOfSubject
            OneOrMore(.anyNonNewline)
            "SDK_VARIANT:"
            Capture(as: variantRef) {
                OneOrMore("a"..."z")
            }
            Anchor.endOfSubject
        }

        guard let firstMatch = try? regex.firstMatch(in: rawGUID) else { return nil }

        return String(firstMatch[variantRef])
    }
}
