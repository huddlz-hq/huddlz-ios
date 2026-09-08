import MapKit
import Testing
@testable import Huddlz

@MainActor
struct SignupLocationBehaviorTests {
    @Test("A city without a time zone cannot be saved as home")
    func incompleteCityCannotBeSaved() async throws {
        let client = AccountClient { request in
            Issue.record("An incomplete city must not reach the profile API")
            return HTTPFixture.response(request, body: Self.savedCity)
        }
        let city = DiscoveryPlace(name: "St. Augustine, FL, USA", latitude: 29.9, longitude: -81.31, timeZone: nil)
        await #expect(throws: (any Error).self) {
            try await client.saveHomeLocation(userID: "neighbor", token: "fixture-token", place: city)
        }
    }

    @Test("Confirming a detected home city saves its center and time zone with the signed-in account")
    func confirmedCitySavesCenterInsteadOfGPSFix() async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var saved = false
        let client = AccountClient { request in
            if request.url?.path == "/api/auth/register" {
                return HTTPFixture.response(request, body: Self.session, status: 201)
            }
            #expect(request.url?.absoluteString == "https://huddlz.com/gql")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let variables = try #require(body["variables"] as? [String: Any])
            #expect(variables["id"] as? String == "neighbor")
            let input = try #require(variables["input"] as? [String: Any])
            #expect(input["homeLocation"] as? String == "St. Augustine, FL, USA")
            #expect(input["homeLatitude"] as? Double == 29.9)
            #expect(input["homeLongitude"] as? Double == -81.31)
            #expect(input["homeTimeZone"] as? String == "America/New_York")
            saved = true
            return HTTPFixture.response(request, body: Self.savedCity)
        }
        let account = AccountStore(client: client, tokens: tokens)
        await register(account)
        let lookup = HomeCityLookup(reverse: { location in
            #expect(location.coordinate.latitude == 29.9012)
            #expect(location.coordinate.longitude == -81.3124)
            return "St. Augustine, FL, USA"
        }, search: { request in
            #expect(request.naturalLanguageQuery == "St. Augustine, FL, USA")
            #expect(request.resultTypes == .address)
            #expect(request.addressFilter?.includes(.locality) == true)
            #expect(request.addressFilter?.excludes(.postalCode) == true)
            return [Self.cityItem()]
        })
        let city = try await lookup.city(near: Self.gpsFix)
        #expect(city == DiscoveryPlace(name: "St. Augustine, FL, USA", latitude: 29.9,
                                      longitude: -81.31, timeZone: "America/New_York"))
        #expect(!saved)
        try await account.saveHomeLocation(city)
        #expect(saved)
        #expect(account.user?.id == "neighbor")
        #expect(try await tokens.load() == "fixture-token")
    }

    @Test("A rejected home-city save keeps the account signed in and can be retried", arguments: [
        #"{"data":{"updateHomeLocation":{"result":{"id":"neighbor","homeLocation":"St. Augustine, FL, USA"},"errors":[{}]}}}"#,
        #"{"data":{"updateHomeLocation":{"result":{"id":"neighbor","homeLocation":"St. Augustine, FL, USA"},"errors":[]}},"errors":[{}]}"#,
        #"{"data":{"updateHomeLocation":{"result":null,"errors":[]}}}"#,
        #"{"data":null}"#,
        "unreadable response"
    ])
    func rejectedSaveCanRetry(response: String) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var shouldFail = true
        let client = AccountClient { request in
            if request.url?.path == "/api/auth/register" {
                return HTTPFixture.response(request, body: Self.session, status: 201)
            }
            return HTTPFixture.response(request, body: shouldFail ? response : Self.savedCity)
        }
        let account = AccountStore(client: client, tokens: tokens)
        await register(account)
        let city = DiscoveryPlace(name: "St. Augustine, FL, USA", latitude: 29.9, longitude: -81.31,
                                  timeZone: "America/New_York")
        await #expect(throws: (any Error).self) { try await account.saveHomeLocation(city) }
        #expect(!account.isBusy)
        #expect(account.user?.id == "neighbor")
        #expect(try await tokens.load() == "fixture-token")
        shouldFail = false
        try await account.saveHomeLocation(city)
        #expect(!account.isBusy)
    }

    @Test("An unresolved or ambiguous current city leaves selection to the person", arguments: [0, 2])
    func unresolvedCityDoesNotChooseAResult(count: Int) async {
        let lookup = HomeCityLookup(reverse: { _ in "Springfield" },
                                    search: { _ in Array(repeating: Self.cityItem(), count: count) })
        await #expect(throws: (any Error).self) { try await lookup.city(near: Self.gpsFix) }
    }

    @Test("City search omits results that lack a time zone")
    func incompleteCityIsNotOffered() async {
        let search = PlaceSearchStore(citiesOnly: true) { _ in
            let incomplete = Self.cityItem()
            incomplete.timeZone = nil
            return [incomplete]
        }
        await search.search("St. Augustine")
        #expect(search.didSearch)
        #expect(search.places.isEmpty)
    }

    @Test("Cancelling a city lookup discards its late result")
    func cancelledLookupCannotSuggestACity() async {
        let pending = PendingCity()
        let lookup = HomeCityLookup(reverse: { _ in await pending.fetch() },
                                    search: { _ in [Self.cityItem()] })
        let task = Task { try await lookup.city(near: Self.gpsFix) }
        await pending.waitUntilRequested()
        task.cancel()
        pending.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func register(_ account: AccountStore) async {
        await account.register(displayName: "Our Neighbor", email: "neighbor@example.com",
                               password: "sample-password", confirmation: "sample-password", legalAcceptance: true)
    }

    private static func cityItem() -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: 29.9, longitude: -81.31),
                             address: MKAddress(fullAddress: "St. Augustine, FL, USA", shortAddress: "St. Augustine"))
        item.timeZone = TimeZone(identifier: "America/New_York")
        return item
    }

    private static let gpsFix = DiscoveryPlace(name: "Current location", latitude: 29.9012, longitude: -81.3124, timeZone: nil)
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}}"#
    private static let savedCity = #"{"data":{"updateHomeLocation":{"result":{"id":"neighbor","homeLocation":"St. Augustine, FL, USA"},"errors":[]}}}"#
}


@MainActor
private final class PendingCity {
    private var response: CheckedContinuation<String?, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch() async -> String? {
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

    func finish() {
        response?.resume(returning: "St. Augustine")
        response = nil
    }
}
