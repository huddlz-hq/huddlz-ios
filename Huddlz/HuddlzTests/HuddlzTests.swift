import Foundation
import Testing
@testable import Huddlz

@MainActor
struct DiscoveryBehaviorTests {
    @Test("A late batch cannot alter a newer search or its filters", arguments: [200, 503])
    func oldPageCannotAlterANewSearch(status: Int) async {
        let pending = PendingHTTPResponse()
        let client = DiscoveryClient { request in
            let parameters = HTTPFixture.parameters(request)
            if parameters["query"] == "hike", parameters["event_type"] == "virtual" {
                return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
            }
            if parameters["page[after]"] != nil { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee],
                next: "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=coffee"))
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(DiscoveryQuery())
        let page = Task { await discovery.loadMore() }
        await pending.waitUntilRequested()
        await discovery.search(DiscoveryQuery(text: "hike", eventType: .virtual))
        pending.finish(body: HTTPFixture.page([HTTPFixture.coffee]), status: status)
        await page.value
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        #expect(discovery.moreError == nil)
        #expect(discovery.nextPage == nil)
        #expect(!discovery.isLoadingMore)
    }

    @Test("Repeated loading preserves cards, requests one batch at a time, and stops at the end")
    func paginationLoadsOnceAndStopsAtTheEnd() async {
        let pending = PendingHTTPResponse()
        var pageAttempts = 0
        let client = DiscoveryClient { request in
            if HTTPFixture.parameters(request)["page[after]"] == nil {
                return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee],
                    next: "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=coffee"))
            }
            pageAttempts += 1
            if pageAttempts == 1 { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(DiscoveryQuery())
        let page = Task { await discovery.loadMore() }
        await pending.waitUntilRequested()
        await discovery.loadMore()
        #expect(pageAttempts == 1)
        #expect(discovery.isLoadingMore)
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
        pending.finish(body: HTTPFixture.page([HTTPFixture.hike]))
        await page.value
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(discovery.nextPage == nil)
        #expect(!discovery.isLoadingMore)
        await discovery.loadMore()
        #expect(pageAttempts == 1)
    }

    @Test("Refresh keeps cards until success and preserves them on failure or cancellation", arguments: [200, 503, -1])
    func refreshKeepsCards(status: Int) async {
        let pending = PendingHTTPResponse()
        let next = "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=coffee"
        var attempts = 0
        let query = DiscoveryQuery(text: "coffee", dates: .thisWeek, eventType: .inPerson)
        let client = DiscoveryClient { request in
            #expect(HTTPFixture.parameters(request)["query"] == "coffee")
            #expect(HTTPFixture.parameters(request)["date_filter"] == "this_week")
            #expect(HTTPFixture.parameters(request)["event_type"] == "in_person")
            attempts += 1
            if attempts > 1 { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee], next: next))
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(query)
        let refresh = Task { await discovery.refresh(query) }
        await pending.waitUntilRequested()
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
        #expect(!discovery.isLoading)
        #expect(discovery.isRefreshing)

        if status == -1 { refresh.cancel() }
        pending.finish(body: HTTPFixture.page([HTTPFixture.hike]), status: status == -1 ? 200 : status)
        await refresh.value
        #expect(discovery.huddlz.map(\.id) == (status == 200 ? ["hike"] : ["coffee"]))
        #expect(discovery.nextPage?.absoluteString == (status == 200 ? nil : next))
        #expect(!discovery.isRefreshing)
        #expect((discovery.refreshError != nil) == (status == 503))
        #expect(discovery.errorMessage == nil)
    }

    @Test("An older refresh cannot replace a newer search or show its error", arguments: [200, 503])
    func olderRefreshCannotReplaceNewSearch(status: Int) async {
        let pending = PendingHTTPResponse()
        var coffeeRequests = 0
        let client = DiscoveryClient { request in
            if HTTPFixture.parameters(request)["query"] == "hike" {
                return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
            }
            coffeeRequests += 1
            if coffeeRequests > 1 { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee]))
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(DiscoveryQuery(text: "coffee"))
        let refresh = Task { await discovery.refresh(DiscoveryQuery(text: "coffee")) }
        await pending.waitUntilRequested()
        await discovery.search(DiscoveryQuery(text: "hike"))
        pending.finish(body: HTTPFixture.page([HTTPFixture.coffee]), status: status)
        await refresh.value

        #expect(discovery.huddlz.map(\.id) == ["hike"])
        #expect(discovery.refreshError == nil)
        #expect(discovery.errorMessage == nil)
        #expect(!discovery.isRefreshing)
    }

    @Test("An invalid image URL does not hide an otherwise readable huddl")
    func invalidImageDoesNotHideEvent() async throws {
        let event = HTTPFixture.coffee.replacingOccurrences(of: "\"thumbnail_url\":null",
                                                          with: "\"image_url\":\"https://[\"")
        let client = DiscoveryClient { request in
            let body = request.url?.path == "/api/json/huddlz/coffee"
                ? "{\"data\":\(event)}" : HTTPFixture.page([event])
            return HTTPFixture.response(request, body: body)
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(DiscoveryQuery())
        #expect(discovery.huddlz.map(\.title) == ["Coffee with neighbors"])
        #expect(discovery.errorMessage == nil)
        let detail = try await client.detail(id: "coffee")
        #expect(detail.title == "Coffee with neighbors")
    }
    @Test("Choosing a place finds nearby huddlz without losing the other filters")
    func choosingPlacePreservesFilters() async {
        let client = DiscoveryClient { request in
            let parameters = HTTPFixture.parameters(request)
            let matches = parameters["query"] == "coffee"
                && parameters["date_filter"] == "this_week"
                && parameters["event_type"] == "in_person"
                && parameters["search_latitude"] == "29.9012"
                && parameters["search_longitude"] == "-81.3124"
                && parameters["distance_miles"] == "25"
                && parameters["search_time_zone"] == "America/New_York"
            return HTTPFixture.response(request, body: HTTPFixture.page(matches ? [HTTPFixture.coffee] : []))
        }
        let discovery = DiscoveryStore(client: client)
        var query = DiscoveryQuery(text: "coffee", dates: .thisWeek, eventType: .inPerson,
                                   timeZone: "America/Los_Angeles")
        query.place = DiscoveryPlace(name: "St. Augustine, FL, USA", latitude: 29.9012,
                                     longitude: -81.3124, timeZone: "America/New_York")

        await discovery.search(query)

        #expect(discovery.huddlz.map(\.title) == ["Coffee with neighbors"])
        #expect(discovery.errorMessage == nil)
    }
    @Test("Visitors can browse public huddlz without signing in")
    func browseWithoutSigningIn() async {
        let client = DiscoveryClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.url?.path == "/api/json/huddlz")
            #expect(HTTPFixture.parameters(request)["date_filter"] == "upcoming")
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee]))
        }
        let discovery = DiscoveryStore(client: client)

        await discovery.search(DiscoveryQuery())

        #expect(discovery.huddlz.map(\.title) == ["Coffee with neighbors"])
        #expect(discovery.huddlz.first?.location == "Juniper Café")
        #expect(discovery.errorMessage == nil)
        #expect(!discovery.isLoading)
    }
    @Test("Date and event-type filters preserve the submitted search")
    func filtersPreserveSearch() async {
        let client = DiscoveryClient { request in
            let parameters = HTTPFixture.parameters(request)
            #expect(parameters["query"] == "coffee & tea")
            #expect(parameters["date_filter"] == "this_week")
            #expect(parameters["event_type"] == "virtual")
            #expect(parameters["search_time_zone"] == "America/New_York")
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee]))
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(DiscoveryQuery(text: " coffee & tea ", dates: .thisWeek,
                                               eventType: .virtual, timeZone: "America/New_York"))
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
    }
    @Test("Loading ends after success, failure, or cancellation", arguments: [200, 503, -1])
    func loadingEnds(status: Int) async {
        let pending = PendingHTTPResponse()
        let discovery = DiscoveryStore(client: DiscoveryClient(fetch: pending.fetch))
        let search = Task { await discovery.search(DiscoveryQuery()) }
        await pending.waitUntilRequested()
        #expect(discovery.isLoading)

        if status == -1 { search.cancel() }
        pending.finish(body: HTTPFixture.page([HTTPFixture.coffee]), status: status == -1 ? 200 : status)
        await search.value

        #expect(!discovery.isLoading)
        if status == 200 {
            #expect(discovery.huddlz.map(\.id) == ["coffee"])
        } else {
            #expect(discovery.huddlz.isEmpty)
        }
        #expect((discovery.errorMessage != nil) == (status == 503))
    }
    @Test("An older search cannot replace newer results or end their loading", arguments: [true, false])
    func latestSearchWins(olderFinishesLast: Bool) async {
        let older = PendingHTTPResponse()
        let newer = PendingHTTPResponse()
        let client = DiscoveryClient { request in
            if HTTPFixture.parameters(request)["query"] == "coffee" { return try await older.fetch(request) }
            return try await newer.fetch(request)
        }
        let discovery = DiscoveryStore(client: client)
        let first = Task { await discovery.search(DiscoveryQuery(text: "coffee")) }
        await older.waitUntilRequested()
        let second = Task { await discovery.search(DiscoveryQuery(text: "hike")) }
        await newer.waitUntilRequested()

        if olderFinishesLast {
            newer.finish(body: HTTPFixture.page([HTTPFixture.hike]))
            await second.value
            older.finish(body: HTTPFixture.page([HTTPFixture.coffee]))
            await first.value
        } else {
            older.finish(body: HTTPFixture.page([HTTPFixture.coffee]))
            await first.value
            #expect(discovery.isLoading)
            #expect(discovery.huddlz.isEmpty)
            newer.finish(body: HTTPFixture.page([HTTPFixture.hike]))
            await second.value
        }
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        #expect(discovery.errorMessage == nil)
        #expect(!discovery.isLoading)
    }
    @Test("A failed next page can be retried without losing or duplicating cards")
    func retryingNextPageRetainsCards() async {
        let next = "https://huddlz.com/api/json/huddlz?date_filter=upcoming&page%5Bafter%5D=coffee"
        var replies = [
            (200, HTTPFixture.page([HTTPFixture.coffee], next: next)),
            (503, "{}"),
            (200, HTTPFixture.page([HTTPFixture.coffee, HTTPFixture.hike]))
        ]
        let client = DiscoveryClient { request in
            if replies.count < 3 { #expect(request.url?.absoluteString == next) }
            let (status, body) = replies.removeFirst()
            return HTTPFixture.response(request, body: body, status: status)
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(DiscoveryQuery())
        await discovery.loadMore()
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
        #expect(discovery.moreError != nil)
        #expect(discovery.nextPage != nil)
        #expect(!discovery.isLoadingMore)

        await discovery.loadMore()
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(discovery.moreError == nil)
        #expect(discovery.nextPage == nil)
        #expect(!discovery.isLoadingMore)
    }
    @Test("Cancelling a pending page allows loading that page again")
    func cancelledPageCanRetry() async {
        let pending = PendingHTTPResponse()
        var pageAttempts = 0
        let client = DiscoveryClient { request in
            if HTTPFixture.parameters(request)["page[after]"] == nil {
                return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee],
                    next: "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=coffee"))
            }
            pageAttempts += 1
            if pageAttempts == 1 { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
        }
        let discovery = DiscoveryStore(client: client)
        await discovery.search(DiscoveryQuery())
        let page = Task { await discovery.loadMore() }
        await pending.waitUntilRequested()
        #expect(discovery.isLoadingMore)
        page.cancel()
        pending.finish(body: HTTPFixture.page([HTTPFixture.hike]))
        await page.value
        #expect(!discovery.isLoadingMore)
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
        #expect(discovery.moreError == nil)

        await discovery.loadMore()
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])
    }
}

@MainActor
enum HTTPFixture {
    static let coffee = """
    {"type":"huddl","id":"coffee","attributes":{
      "title":"Coffee with neighbors","description":"Bring a mug and meet your neighbors.",
      "starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T16:00:00.000000Z",
      "time_zone":"America/New_York","event_type":"in_person",
      "physical_location":"Juniper Café","thumbnail_url":null,"lifecycle_state":"published"
    }}
    """
    static let hike = """
    {"type":"huddl","id":"hike","attributes":{
      "title":"Riverside hike","description":null,
      "starts_at":"2026-09-11T13:00:00Z","ends_at":"2026-09-11T15:00:00Z",
      "time_zone":"America/New_York","event_type":"in_person",
      "physical_location":null,"thumbnail_url":null,"lifecycle_state":"published"
    }}
    """

    static func page(_ events: [String], next: String? = nil) -> String {
        let link = next.map { "\"\($0)\"" } ?? "null"
        return "{\"data\":[\(events.joined(separator: ","))],\"links\":{\"next\":\(link)}}"
    }

    static func response(_ request: URLRequest, body: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/vnd.api+json"])!)
    }

    static func parameters(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            .queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
    }
}

/// Holds an HTTP response until the test releases it, without timing sleeps.
@MainActor
final class PendingHTTPResponse {
    private var request: URLRequest?
    private var response: CheckedContinuation<(Data, URLResponse), Error>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.request = request
            response = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilRequested() async {
        if request != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(body: String, status: Int = 200) {
        response?.resume(returning: HTTPFixture.response(request!, body: body, status: status))
        response = nil
    }
}
