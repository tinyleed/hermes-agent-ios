import Foundation

public struct HermesGatewayRemoteConnection: Equatable, Sendable {
    public let baseURL: URL
    public let sessionToken: String

    public init(baseURL: URL, sessionToken: String) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
    }

    public static func normalizeBaseURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HermesGatewayRemoteConnectionError.missingBaseURL }
        guard var components = URLComponents(string: trimmed) else { throw HermesGatewayRemoteConnectionError.invalidBaseURL }
        guard components.scheme == "http" || components.scheme == "https" else { throw HermesGatewayRemoteConnectionError.unsupportedScheme }
        components.fragment = nil
        components.queryItems = nil
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty {
            components.path = "/" + components.path
        }
        guard let url = components.url else { throw HermesGatewayRemoteConnectionError.invalidBaseURL }
        return url
    }

    public static func webSocketURL(baseURL: URL, sessionToken: String) throws -> URL {
        let token = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw HermesGatewayRemoteConnectionError.missingSessionToken }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw HermesGatewayRemoteConnectionError.invalidBaseURL }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = (prefix.isEmpty ? "" : "/\(prefix)") + "/api/ws"
        components.percentEncodedQuery = "token=\(percentEncodeQueryValue(token))"
        guard let url = components.url else { throw HermesGatewayRemoteConnectionError.invalidBaseURL }
        return url
    }

    private static func percentEncodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    public var webSocketURL: URL {
        get throws { try Self.webSocketURL(baseURL: baseURL, sessionToken: sessionToken) }
    }
}

public enum HermesGatewayRemoteConnectionError: LocalizedError, Equatable {
    case missingBaseURL
    case invalidBaseURL
    case unsupportedScheme
    case missingSessionToken

    public var errorDescription: String? {
        switch self {
        case .missingBaseURL: "Remote Hermes gateway URL is missing"
        case .invalidBaseURL: "Remote Hermes gateway URL is invalid"
        case .unsupportedScheme: "Remote Hermes gateway URL must use http:// or https://"
        case .missingSessionToken: "Remote Hermes gateway session token is missing"
        }
    }
}
