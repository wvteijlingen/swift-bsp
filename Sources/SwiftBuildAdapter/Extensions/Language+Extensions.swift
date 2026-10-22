import LanguageServerProtocol
import SwiftBuild

extension Language {
    init?(_ language: SWBSourceLanguage) {
        switch language {
        case .c: self = .c
        case .cpp: self = .cpp
        case .metal: return nil
        case .objectiveC: self = .objective_c
        case .objectiveCpp: self = .objective_cpp
        case .swift: self = .swift
        }
    }
}
