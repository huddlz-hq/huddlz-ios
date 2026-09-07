#if DEBUG
import MapKit

/// Replaces Apple's external place search while keeping the place mapping and UI real.
@MainActor
final class UITestMapSearchService {
    static let shared: UITestMapSearchService? = {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HUDDLZ_UI_HTTP_SCRIPT"] != nil || environment["HUDDLZ_UI_MAP_SCRIPT"] != nil else { return nil }
        return UITestMapSearchService(script: environment["HUDDLZ_UI_MAP_SCRIPT"] ?? "[]")
    }()

    private struct Route: Decodable {
        let query: String
        let results: [Place]
    }
    private struct Place: Decodable {
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let timeZone: String?
    }
    private let routes: [Route]

    private init(script: String) {
        routes = (try? JSONDecoder().decode([Route].self, from: Data(script.utf8))) ?? []
    }

    func search(_ request: MKLocalSearch.Request) throws -> [MKMapItem] {
        guard let route = routes.first(where: { $0.query == request.naturalLanguageQuery }) else {
            throw URLError(.badServerResponse)
        }
        return route.results.map { place in
            let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude),
                                 address: MKAddress(fullAddress: place.address, shortAddress: place.name))
            item.name = place.name
            item.timeZone = place.timeZone.flatMap(TimeZone.init(identifier:))
            return item
        }
    }
}
#endif
