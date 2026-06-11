import Foundation
import HermesAgentCore

struct GatewaySettings: Equatable, Sendable {
    let baseURL: URL
    let hermesAPIBaseURL: URL
    let hermesBearerToken: String?

    static let mockGateway = GatewaySettings(
        baseURL: URL(string: "http://127.0.0.1:8787")!,
        hermesAPIBaseURL: URL(string: "http://127.0.0.1:8642")!,
        hermesBearerToken: nil
    )

    static let hermesAPIServer = GatewaySettings(
        baseURL: URL(string: "http://127.0.0.1:8787")!,
        hermesAPIBaseURL: URL(string: "http://127.0.0.1:8642")!,
        hermesBearerToken: nil
    )

    var client: GatewayClient {
        GatewayClient(baseURL: baseURL)
    }

    var hermesClient: HermesAPIClient {
        HermesAPIClient(baseURL: hermesAPIBaseURL, bearerToken: hermesBearerToken)
    }

    func request(for endpoint: GatewayEndpoint) throws -> URLRequest {
        try endpoint.urlRequest(baseURL: baseURL)
    }

    func hermesRequest(for endpoint: HermesAPIEndpoint) throws -> URLRequest {
        try endpoint.urlRequest(baseURL: hermesAPIBaseURL, bearerToken: hermesBearerToken)
    }
}
