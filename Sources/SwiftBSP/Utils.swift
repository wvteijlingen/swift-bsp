import Subprocess


func succeedAndGetOutput(_ executable: Executable, _ arguments: Arguments = []) async throws -> String {
    try await succeedAndGetOutput(Configuration(executable: executable, arguments: arguments))
}

func succeedAndGetOutput(_ config: Configuration) async throws -> String {
    let result = try await run(config, output: .string(limit: .max), error: .string(limit: .max))

    if result.terminationStatus.exitCode != 0 {
        throw BuildServerError.subprocessFailure(
            """
            Command: \(config.executable) \(config.arguments.description)
            Exit status \(result.terminationStatus)
            Stderr:
            \(result.standardError ?? "")
            """
        )
    }

    return result.standardOutput ?? ""
}


//extension CollectedResult {
//    @discardableResult
//    func exitIfFailed() -> Self {
//        if terminationStatus.exitCode != 0 {
//            exit(terminationStatus.exitCode)
//        }
//        return self
//    }
//}

extension TerminationStatus {
    var exitCode: Int32 {
        switch self {
            case .exited(let code): code
            case .signaled(let code): code
        }
    }
}
