import MapKit

/// Resolves a GPS fix to a city center before a person confirms their home city.
@MainActor
struct HomeCityLookup {
    private let reverse: (CLLocation) async throws -> String?
    private let search: ((MKLocalSearch.Request) async throws -> [MKMapItem])?

    init(reverse: ((CLLocation) async throws -> String?)? = nil,
         search: ((MKLocalSearch.Request) async throws -> [MKMapItem])? = nil) {
        self.search = search
        if let reverse {
            self.reverse = reverse
        } else {
            self.reverse = { location in
                #if DEBUG
                if ProcessInfo.processInfo.environment["HUDDLZ_UI_HTTP_SCRIPT"] != nil {
                    guard let city = ProcessInfo.processInfo.environment["HUDDLZ_UI_REVERSE_CITY"],
                          !city.isEmpty else { throw CLError(.geocodeFoundNoResult) }
                    return city
                }
                #endif
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    throw CLError(.geocodeFoundNoResult)
                }
                let items = try await request.mapItems
                return items.first?.addressRepresentations?.cityWithContext(.full)
            }
        }
    }

    func city(near location: DiscoveryPlace) async throws -> DiscoveryPlace {
        let fix = CLLocation(latitude: location.latitude, longitude: location.longitude)
        guard let name = try await reverse(fix), !name.isEmpty else {
            throw CLError(.geocodeFoundNoResult)
        }
        try Task.checkCancellation()
        let cities = PlaceSearchStore(citiesOnly: true, fetch: search)
        await cities.search(name)
        try Task.checkCancellation()
        guard cities.places.count == 1, let city = cities.places.first else {
            throw CLError(.geocodeFoundNoResult)
        }
        return city
    }
}
