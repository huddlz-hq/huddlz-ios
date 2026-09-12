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
}
