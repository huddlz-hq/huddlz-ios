import MapKit
import Observation

@MainActor
@Observable
final class PlaceSearchStore {
    private(set) var places: [DiscoveryPlace] = []
    private(set) var isLoading = false
    private(set) var didSearch = false
    private(set) var errorMessage: String?
    private let citiesOnly: Bool
    private var revision = UUID()
    private let fetch: (MKLocalSearch.Request) async throws -> [MKMapItem]

    init(citiesOnly: Bool = false, fetch: ((MKLocalSearch.Request) async throws -> [MKMapItem])? = nil) {
        self.citiesOnly = citiesOnly
        if let fetch {
            self.fetch = fetch
        } else {
            #if DEBUG
            if let service = UITestMapSearchService.shared {
                self.fetch = { try service.search($0) }
                return
            }
            #endif
            self.fetch = { request in
                try await MKLocalSearch(request: request).start().mapItems
            }
        }
    }

    func clear() {
        revision = UUID()
        places = []
        isLoading = false
        didSearch = false
        errorMessage = nil
    }

    func search(_ text: String) async {
        clear()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let current = revision
        isLoading = true
        defer { if revision == current { isLoading = false } }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        if citiesOnly { request.addressFilter = MKAddressFilter(including: [.locality]) }
        do {
            let items = try await fetch(request)
            guard revision == current, !Task.isCancelled else { return }
            places = items.filter { !citiesOnly || $0.timeZone != nil }.map { item in
                DiscoveryPlace(name: item.address?.fullAddress ?? item.name ?? text,
                               latitude: item.location.coordinate.latitude,
                               longitude: item.location.coordinate.longitude,
                               timeZone: item.timeZone?.identifier)
            }
            didSearch = true
        } catch {
            guard revision == current, !Task.isCancelled else { return }
            didSearch = true
            if (error as? MKError)?.code != .placemarkNotFound {
                errorMessage = "Places couldn’t load. Check your connection and try again."
            }
        }
    }
}
