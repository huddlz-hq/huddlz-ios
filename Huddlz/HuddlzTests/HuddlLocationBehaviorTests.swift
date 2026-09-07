import MapKit
import Testing
@testable import Huddlz

@MainActor
struct HuddlLocationBehaviorTests {
    @Test("An unresolved venue sends its complete address to Maps search", arguments: [-1, 0, 2])
    func openUnresolvedVenue(resultCount: Int) async {
        let location = HuddlLocationStore(address: "Café & Co, 12 Main St #2, Montréal") { _ in
            if resultCount < 0 { throw URLError(.notConnectedToInternet) }
            return (0..<resultCount).map { _ in
                MKMapItem(location: CLLocation(latitude: 45.5, longitude: -73.6), address: nil)
            }
        }
        await location.resolve()
        var opened: URL?
        location.open(place: { _ in Issue.record("An unresolved venue must open a search") }, search: { opened = $0 })
        let request = opened.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(request?.scheme == "https")
        #expect(request?.host == "maps.apple.com")
        #expect(request?.queryItems == [URLQueryItem(name: "q", value: "Café & Co, 12 Main St #2, Montréal")])
    }

    @Test("Opening a resolved venue sends its place and coordinates to Maps")
    func openResolvedVenue() async {
        let location = HuddlLocationStore(address: "1 Apple Park Way, Cupertino, CA") { request in
            #expect(request.naturalLanguageQuery == "1 Apple Park Way, Cupertino, CA")
            let item = MKMapItem(location: CLLocation(latitude: 37.3349, longitude: -122.0090), address: nil)
            item.name = "Apple Park"
            return [item]
        }
        await location.resolve()
        var opened: MKMapItem?
        location.open(place: { opened = $0 }, search: { _ in Issue.record("Expected a resolved place") })
        #expect(opened?.name == "Apple Park")
        #expect(opened?.location.coordinate.latitude == 37.3349)
        #expect(opened?.location.coordinate.longitude == -122.0090)
    }
}
