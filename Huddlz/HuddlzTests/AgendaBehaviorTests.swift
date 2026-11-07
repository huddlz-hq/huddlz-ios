import Foundation
import Testing
@testable import Huddlz

@MainActor
struct AgendaBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#

    private static func huddl(_ id: String, starts: String, ends: String, zone: String, attendance: String) -> String {
        #"{"type":"huddl","id":"\#(id)","attributes":{"title":"\#(id)","starts_at":"\#(starts)","ends_at":"\#(ends)","time_zone":"\#(zone)","event_type":"in_person","lifecycle_state":"published","attendance_state":"\#(attendance)"}}"#
    }

    @Test("The agenda groups RSVPs by day in each huddl's time zone, soonest first, and drops rows without an RSVP")
    func agendaGroupsByLocalDay() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        // 23:00Z on the 15th is still the 15th in New York but already the 16th in Paris.
        let rows = [
            Self.huddl("paris", starts: "2026-09-15T23:00:00Z", ends: "2026-09-16T00:00:00Z", zone: "Europe/Paris", attendance: "waitlisted"),
            Self.huddl("coffee", starts: "2026-09-14T13:00:00Z", ends: "2026-09-14T15:00:00Z", zone: "America/New_York", attendance: "confirmed"),
            Self.huddl("skipped", starts: "2026-09-14T14:00:00Z", ends: "2026-09-14T15:00:00Z", zone: "America/New_York", attendance: "none"),
            Self.huddl("hike", starts: "2026-09-15T22:00:00Z", ends: "2026-09-16T00:00:00Z", zone: "America/New_York", attendance: "confirmed")
        ]
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/huddlz/upcoming" else { return HTTPFixture.response(request, body: Self.session) }
            return HTTPFixture.response(request, body: "{\"data\":[\(rows.joined(separator: ","))]}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = AgendaStore()
        await store.load(account: account)
        #expect(store.days.map(\.dateKey) == ["2026-09-14", "2026-09-15", "2026-09-16"])
        #expect(store.days.map { $0.entries.map(\.id) } == [["coffee"], ["hike"], ["paris"]])
        #expect(store.days.last?.entries.first?.attendance == .waitlisted)
    }

    @Test("Agenda rows name the venue, not the whole street address", arguments: [
        ("Juniper Café, 12 Elm Street, Austin, TX, USA", "Juniper Café"),
        ("Juniper Café", "Juniper Café")
    ])
    func agendaRowsNameTheVenue(address: String, venue: String) async throws {
        let event = HTTPFixture.coffee.replacingOccurrences(of: "Juniper Café", with: address)
        let client = DiscoveryClient { request in
            HTTPFixture.response(request, body: "{\"data\":\(event)}")
        }
        let huddl = try await client.detail(id: "coffee")
        #expect(huddl.venueName == venue)
    }

    @Test("The agenda stays soonest first when a local date repeats across time zones")
    func agendaKeepsChronologicalOrderAcrossTimeZones() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let rows = [
            Self.huddl("los-angeles", starts: "2026-09-15T06:30:00Z", ends: "2026-09-15T07:30:00Z", zone: "America/Los_Angeles", attendance: "confirmed"),
            Self.huddl("paris", starts: "2026-09-15T06:00:00Z", ends: "2026-09-15T07:00:00Z", zone: "Europe/Paris", attendance: "waitlisted"),
            Self.huddl("new-york-later", starts: "2026-09-15T03:30:00Z", ends: "2026-09-15T04:30:00Z", zone: "America/New_York", attendance: "confirmed"),
            Self.huddl("new-york", starts: "2026-09-15T03:00:00Z", ends: "2026-09-15T04:00:00Z", zone: "America/New_York", attendance: "confirmed")
        ]
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/huddlz/upcoming" else { return HTTPFixture.response(request, body: Self.session) }
            return HTTPFixture.response(request, body: "{\"data\":[\(rows.joined(separator: ","))]}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = AgendaStore()
        await store.load(account: account)
        #expect(store.days.map { $0.entries.map(\.id) } == [["new-york", "new-york-later"], ["paris"], ["los-angeles"]])
        #expect(store.days.count == 3)
        #expect(store.days.first?.title == store.days.last?.title)
        #expect(Set(store.days.map(\.id)).count == store.days.count)
    }

    @Test("An agenda response that arrives after signing out cannot fill the list")
    func lateAgendaCannotOutliveTheAccount() async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            switch request.url?.path {
            case "/api/json/huddlz/upcoming": return try await pending.fetch(request)
            case "/api/auth/sign_out": return HTTPFixture.response(request, body: "", status: 204)
            default: return HTTPFixture.response(request, body: Self.session)
            }
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = AgendaStore()
        let loading = Task { await store.load(account: account) }
        await pending.waitUntilRequested()
        await account.signOut()
        pending.finish(body: "{\"data\":[\(Self.huddl("coffee", starts: "2026-09-14T13:00:00Z", ends: "2026-09-14T15:00:00Z", zone: "America/New_York", attendance: "confirmed"))]}")
        await loading.value
        #expect(store.days.isEmpty)
        #expect(store.loadedUserID == nil)
        #expect(!store.loadFailed)
    }

    @Test("An empty agenda loads without an error")
    func emptyAgenda() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/huddlz/upcoming" else { return HTTPFixture.response(request, body: Self.session) }
            return HTTPFixture.response(request, body: #"{"data":[]}"#)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = AgendaStore()
        await store.load(account: account)
        #expect(store.days.isEmpty)
        #expect(!store.loadFailed)
        #expect(store.loadedUserID == "neighbor")
    }

    @Test("A failed agenda load can be retried", arguments: [503, -1])
    func failedAgendaCanRetry(status: Int) async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var attempts = 0
        let coffee = Self.huddl("coffee", starts: "2099-09-14T13:00:00Z", ends: "2099-09-14T15:00:00Z", zone: "America/New_York", attendance: "confirmed")
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/huddlz/upcoming" else { return HTTPFixture.response(request, body: Self.session) }
            attempts += 1
            if attempts == 1 {
                if status < 0 { throw URLError(.notConnectedToInternet) }
                return HTTPFixture.response(request, body: "{}", status: status)
            }
            return HTTPFixture.response(request, body: "{\"data\":[\(coffee)]}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = AgendaStore()
        await store.load(account: account)
        #expect(store.loadFailed)
        #expect(store.days.isEmpty)
        await store.load(account: account)
        #expect(!store.loadFailed)
        #expect(store.days.flatMap(\.entries).map(\.id) == ["coffee"])
    }

    @Test("Cancelling an RSVP removes the huddl when the agenda reloads")
    func cancelledRSVPLeavesTheAgenda() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var cancelled = false
        let coffee = Self.huddl("coffee", starts: "2099-09-14T13:00:00Z", ends: "2099-09-14T15:00:00Z", zone: "America/New_York", attendance: "confirmed")
        let account = AccountStore(client: AccountClient { request in
            switch request.url?.path {
            case "/api/json/huddlz/upcoming":
                return HTTPFixture.response(request, body: cancelled ? #"{"data":[]}"# : "{\"data\":[\(coffee)]}")
            case "/api/json/huddlz/coffee/cancel_rsvp":
                cancelled = true
                return HTTPFixture.response(request, body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"none"}}}"#)
            default:
                return HTTPFixture.response(request, body: Self.session)
            }
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let agenda = AgendaStore()
        await agenda.load(account: account)
        #expect(agenda.days.flatMap(\.entries).map(\.id) == ["coffee"])
        let rsvp = HuddlAttendanceStore()
        await rsvp.change(huddlID: "coffee", action: .cancel, account: account)
        #expect(rsvp.attendance == AttendanceState.none)
        #expect(rsvp.actionError == nil)
        await agenda.load(account: account)
        #expect(agenda.days.isEmpty)
    }
}
