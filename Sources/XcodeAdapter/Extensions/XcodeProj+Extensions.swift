import XcodeProj
import BuildServerProtocol

extension XcodeProj {
    var allSchemes: [XCScheme] {
        let userSchemes = userData.flatMap { $0.schemes }
        let sharedSchemes = sharedData?.schemes ?? []
        return userSchemes + sharedSchemes
    }
}

//extension XCScheme {
//    var uri: URI {
//        let escapedName = name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? name
//        return try! URI(string: "xcscheme://\(escapedName)")
//    }
//}
