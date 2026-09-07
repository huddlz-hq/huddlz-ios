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
        let body: String
    }

    private var routes: [Route]

    private init(script: String) {
        // Invalid scripts fail closed: UI tests must never fall through to production.
        routes = (try? JSONDecoder().decode([Route].self, from: Data(script.utf8))) ?? []
    }

    func respond(to request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let index = routes.firstIndex { route in
            route.path == url.path && route.query.allSatisfy { key, value in
                parameters.contains { $0.name == key && $0.value == value }
            }
        }
        var response = Response(status: 500, body: "{\"errors\":[{\"detail\":\"No matching UI test response\"}]}")
        if let index, let first = routes[index].responses.first {
            response = first
            if routes[index].responses.count > 1 { routes[index].responses.removeFirst() }
        }
        try Task.checkCancellation()
        return (Data(response.body.utf8), HTTPURLResponse(url: url, statusCode: response.status,
                                                       httpVersion: nil, headerFields: nil)!)
    }
}
#endif
