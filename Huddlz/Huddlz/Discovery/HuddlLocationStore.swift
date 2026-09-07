import MapKit
import Observation

@MainActor
@Observable
final class HuddlLocationStore {
    let address: String
    private(set) var item: MKMapItem?
    private let fetch: (MKLocalSearch.Request) async throws -> [MKMapItem]

    init(address: String, fetch: ((MKLocalSearch.Request) async throws -> [MKMapItem])? = nil) {
        self.address = address
        if let fetch {
            self.fetch = fetch
        } else {
            #if DEBUG
            if let service = UITestMapSearchService.shared {
                self.fetch = { try service.search($0) }
                return
            }
            #endif
            self.fetch = { try await MKLocalSearch(request: $0).start().mapItems }
        }
    }

    func resolve() async {
        item = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let items = try await fetch(request)
            guard !Task.isCancelled else { return }
            // Leave ambiguous destinations for people to choose in Maps.
            if items.count == 1 { item = items[0] }
        } catch {
            // The address remains available even when the map lookup fails.
        }
    }

    func open(place: (MKMapItem) -> Void, search: (URL) -> Void) {
        if let item {
            place(item)
        } else {
            var url = URLComponents(string: "https://maps.apple.com/")!
            url.queryItems = [URLQueryItem(name: "q", value: address)]
            if let url = url.url { search(url) }
        }
    }
}
