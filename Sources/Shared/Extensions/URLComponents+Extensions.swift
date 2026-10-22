import Foundation

extension URLComponents {
    public init(scheme: String, host: String, queryItems: [String: String]) {
        self.init()
        
        self.scheme = scheme
        self.host = host
        self.queryItems = queryItems.reduce(into: []) { partialResult, item in
            partialResult.append(URLQueryItem(
                name: item.key,
                value: item.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ))
        }
    }

    public func value(forFirstQueryItemWithName name: String) -> String? {
        queryItems?
            .first { $0.name == name }?
            .value?
            .removingPercentEncoding
    }
}
