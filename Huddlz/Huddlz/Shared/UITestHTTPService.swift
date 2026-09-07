#if DEBUG
import Foundation

/// UI tests replace the external service while exercising real requests and decoding.
@MainActor
final class UITestHTTPService {
    static let shared: UITestHTTPService? = {
        guard let script = ProcessInfo.processInfo.environment["HUDDLZ_UI_HTTP_SCRIPT"] else { return nil }
        return UITestHTTPService(script: script)
    }()

    private struct Route: Decodable {
        let path: String
        let query: [String: String]
        var responses: [Response]
    }

    private struct Response: Decodable {
        let status: Int
        var delaySeconds: Double?
        var body: String?
        var bodyBase64: String?
    }

    private var routes: [Route]

    private init(script: String) {
        // Invalid scripts fail closed: UI tests must never fall through to production.
        routes = (try? JSONDecoder().decode([Route].self, from: Data(script.utf8))) ?? []
        URLProtocol.registerClass(UITestImageURLProtocol.self)
    }

    func respond(to request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let index = routes.firstIndex { route in
            route.path == url.path && route.query.allSatisfy { key, value in
                parameters.contains { parameter in
                    guard parameter.name == key else { return false }
                    if key == "search_latitude" || key == "search_longitude",
                       let actual = parameter.value.flatMap(Double.init), let expected = Double(value) {
                        // Core Location can introduce floating-point rounding during simulation.
                        return abs(actual - expected) < 0.00000001
                    }
                    return parameter.value == value
                }
            }
        }
        var response = Response(status: 500, body: "{\"errors\":[{\"detail\":\"No matching UI test response\"}]}")
        if let index, let first = routes[index].responses.first {
            response = first
            if routes[index].responses.count > 1 { routes[index].responses.removeFirst() }
        }
        if let delay = response.delaySeconds {
            try await Task.sleep(for: .seconds(delay))
        }
        try Task.checkCancellation()
        let data = response.bodyBase64.flatMap { Data(base64Encoded: $0) } ?? Data((response.body ?? "").utf8)
        return (data, HTTPURLResponse(url: url, statusCode: response.status,
                                                       httpVersion: nil, headerFields: nil)!)
    }
}

/// AsyncImage keeps its real loader; only its external HTTP response is replaced.
private final class UITestImageURLProtocol: URLProtocol, @unchecked Sendable {
    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        loadingTask = Task { @MainActor in
            do {
                guard let service = UITestHTTPService.shared else { throw URLError(.badServerResponse) }
                let (data, response) = try await service.respond(to: request)
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() { loadingTask?.cancel() }
}
#endif
