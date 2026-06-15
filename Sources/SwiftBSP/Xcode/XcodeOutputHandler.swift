import LanguageServerProtocol
import System

struct XcodeOutputHandler {
    private let regexPattern = /^(.+):(\d+):(\d+): (error|warning|note): (.+)$/

    func handle(line: String) -> XcodeOutput {
        parse(line: line)
    }

    private func parse(line: String) -> XcodeOutput {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = try? regexPattern.wholeMatch(in: trimmedLine) {
            let file = String(match.1)
            let lineNumber = Int(String(match.2))
            let columnNumber = Int(String(match.3))
            let rawSeverity = match.4
            let message = String(match.5)

            guard let lineNumber, let columnNumber else {
                return .output(line)
            }

            let severity: DiagnosticSeverity = switch rawSeverity {
            case "error": .error
            case "warning": .warning
            case "note": .information
            default: .information
            }

            let startPosition = Position(line: lineNumber - 1, utf16index: columnNumber)
            let endPosition = startPosition

            return .diagnostic(
                file: FilePath(file),
                diagnostic: Diagnostic(
                    range: startPosition ..< endPosition,
                    severity: severity,
                    source: "swift-bsp",
                    message: message
                )
            )
        } else {
            return .output(line)
        }
    }
}

enum XcodeOutput: Error {
    case output(String)
    case diagnostic(file: FilePath, diagnostic: Diagnostic)
}
// extension XcodeOutput {
//     struct Diagnostic: Encodable {
//         let severity: Severity
//         let file: String?
//         let line: Int?
//         let column: Int?
//         let message: String
//     }
// }

// extension XcodeOutput {
//     enum Severity: String, Encodable {
//         case error, warning, note
//     }
// }
