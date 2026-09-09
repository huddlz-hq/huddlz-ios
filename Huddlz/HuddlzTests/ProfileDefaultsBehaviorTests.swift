import Foundation
import Testing
@testable import Huddlz

@MainActor
struct ProfileDefaultsBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#
    private static let profile = #"{"id":"neighbor","search_defaults":{"home_location":{"label":"Austin, TX","latitude":30.2672,"longitude":-97.7431,"time_zone":"America/Chicago"},"distance_miles":25}}"#

    @Test("A chosen place or Anywhere wins over a late profile response", arguments: [false, true])
    func explicitLocationWins(chooseAnywhere: Bool) async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/profile" {
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                return try await pending.fetch(request)
            }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let preferences = DiscoveryPreferences()
        preferences.query.text = "coffee"
        preferences.query.dates = .thisWeek
        preferences.query.eventType = .inPerson
        let loading = Task { await preferences.loadProfile(for: account) }
        await pending.waitUntilRequested()
        let chosen = chooseAnywhere ? nil : DiscoveryPlace(name: "Denver, CO", latitude: 39.7392,
                                                           longitude: -104.9903, timeZone: "America/Denver")
        preferences.selectPlace(chosen)
        preferences.query.distanceMiles = 50
        let expected = preferences.query
        pending.finish(body: Self.profile)
        await loading.value
        #expect(preferences.query == expected)

        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let parameters = HTTPFixture.parameters(request)
            let matches = parameters["search_latitude"] == chosen.map { String($0.latitude) }
                && parameters["query"] == "coffee" && parameters["date_filter"] == "this_week"
                && parameters["event_type"] == "in_person"
            return HTTPFixture.response(request, body: HTTPFixture.page(matches ? [HTTPFixture.coffee] : []))
        })
        await discovery.search(preferences.query)
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
    }
    @Test("A missing or unavailable profile city leaves browsing and manual search available", arguments: [200, 503, -1])
    func missingProfileKeepsDiscoveryAvailable(status: Int) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/profile" {
                if status < 0 { throw URLError(.notConnectedToInternet) }
                return HTTPFixture.response(request, body: #"{"id":"neighbor","search_defaults":{"home_location":null,"distance_miles":25}}"#, status: status)
            }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let preferences = DiscoveryPreferences()
        await preferences.loadProfile(for: account)
        #expect(preferences.query.place == nil)
        #expect(account.user?.id == "neighbor")
        #expect(account.message == nil)
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let nearby = HTTPFixture.parameters(request)["search_latitude"] == "39.7392"
            return HTTPFixture.response(request, body: HTTPFixture.page([nearby ? HTTPFixture.coffee : HTTPFixture.hike]))
        })
        await discovery.search(preferences.query)
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        preferences.selectPlace(DiscoveryPlace(name: "Denver, CO", latitude: 39.7392,
                                               longitude: -104.9903, timeZone: "America/Denver"))
        await discovery.search(preferences.query)
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
    }

    @Test("Signing out discards a pending profile city")
    func signOutDiscardsProfile() async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/profile" { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let preferences = DiscoveryPreferences()
        let loading = Task { await preferences.loadProfile(for: account) }
        await pending.waitUntilRequested()
        await account.signOut()
        await preferences.loadProfile(for: account)
        pending.finish(body: Self.profile)
        await loading.value
        #expect(account.user == nil)
        #expect(preferences.query.place == nil)
    }

}
