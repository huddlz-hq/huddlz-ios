import MapKit
import Testing
@testable import Huddlz

@MainActor
struct PlaceSearchBehaviorTests {
    @Test("An unmatched place search can be corrected to find a selectable place")
    func correctUnmatchedPlace() async {
        let search = PlaceSearchStore { request in
            #expect(request.resultTypes == .address)
            return request.naturalLanguageQuery == "St. Augustine" ? [Self.stAugustine()] : []
        }
        await search.search("Unknown place")
        #expect(search.didSearch)
        #expect(search.places.isEmpty)
        #expect(search.errorMessage == nil)
        #expect(!search.isLoading)

        await search.search(" St. Augustine ")
        #expect(search.places == [
            DiscoveryPlace(name: "St. Augustine, FL, USA", latitude: 29.9012,
                           longitude: -81.3124, timeZone: "America/New_York")
        ])
        #expect(search.errorMessage == nil)
        #expect(!search.isLoading)
    }

    @Test("A failed place search can be retried without showing old places")
    func retryFailedPlaceSearch() async {
        var shouldFail = false
        let search = PlaceSearchStore { _ in
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return [Self.stAugustine()]
        }
        await search.search("St. Augustine")
        #expect(search.places.count == 1)
        shouldFail = true
        await search.search("Jacksonville")
        #expect(search.places.isEmpty)
        #expect(search.errorMessage == "Places couldn’t load. Check your connection and try again.")
        #expect(!search.isLoading)

        shouldFail = false
        await search.search("St. Augustine")
        #expect(search.places.first?.name == "St. Augustine, FL, USA")
        #expect(search.errorMessage == nil)
        #expect(!search.isLoading)
    }

    @Test("Editing or replacing a place search discards its pending results", arguments: [true, false])
    func discardOlderPlaces(editOnly: Bool) async {
        let pending = PendingPlaces()
        let search = PlaceSearchStore { request in
            if request.naturalLanguageQuery == "Old" { return await pending.fetch() }
            return []
        }
        let older = Task { await search.search("Old") }
        await pending.waitUntilRequested()
        #expect(search.isLoading)

        if editOnly { search.clear() }
        else { await search.search("New") }
        pending.finish([Self.stAugustine()])
        await older.value

        #expect(search.places.isEmpty)
        #expect(search.didSearch == !editOnly)
        #expect(!search.isLoading)
        #expect(search.errorMessage == nil)
    }

    private static func stAugustine() -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: 29.9012, longitude: -81.3124),
                             address: MKAddress(fullAddress: "St. Augustine, FL, USA", shortAddress: "St. Augustine"))
        item.timeZone = TimeZone(identifier: "America/New_York")
        return item
    }
}

@MainActor
private final class PendingPlaces {
    private var response: CheckedContinuation<[MKMapItem], Never>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch() async -> [MKMapItem] {
        await withCheckedContinuation {
            response = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilRequested() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ places: [MKMapItem]) {
        response?.resume(returning: places)
        response = nil
    }
}
