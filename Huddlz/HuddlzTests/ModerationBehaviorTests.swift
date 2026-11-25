import Darwin
import Foundation
import Testing
@testable import Huddlz

@MainActor
struct ModerationBehaviorTests {
    private static let user = #"{"id":"neighbor","email":"neighbor@example.com"}"#
    private static let session = "{\"token\":\"fixture-token\",\"user\":\(user)}"
    private static let group = #"{"data":{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","description":null,"location":null}}}"#
    nonisolated private static let confirmEmail = "We couldn’t accept your report. If you haven’t confirmed your email address, confirm it and try again."
    nonisolated private static let couldNotSend = "Couldn’t send your report. Check your connection and try again."

    /// A signed-in account whose requests go to `respond`; anything it leaves alone signs the person in.
    private func signedIn(_ respond: @escaping (URLRequest) async throws -> (Data, URLResponse)?) async -> (AccountStore, SessionTokenStore) {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        let account = AccountStore(client: AccountClient { request in
            if let response = try await respond(request) { return response }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        return (account, tokens)
    }

    /// A scripted reply; a negative status stands for a dropped connection.
    private func reply(_ request: URLRequest, status: Int, body: String = "{}") throws -> (Data, URLResponse) {
        if status < 0 { throw URLError(.notConnectedToInternet) }
        return HTTPFixture.response(request, body: body, status: status)
    }

    private func sent(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(body["data"] as? [String: Any])
    }

    // MARK: Reporting

    @Test("A report names the huddl or group and the reason, never an account", arguments: [
        (ModerationSubject.huddl("coffee"), "/api/json/account_reports/organizer", "huddl_id"),
        (ModerationSubject.group("neighbors"), "/api/json/account_reports/group", "group_id")
    ])
    func reportNamesThePageAndReason(subject: ModerationSubject, path: String, key: String) async throws {
        var reports: [[String: Any]] = []
        let (account, tokens) = await signedIn { request in
            guard request.url?.path.hasPrefix("/api/json/account_reports") == true else { return nil }
            #expect(request.url?.path == path)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
            reports.append(try sent(request))
            return HTTPFixture.response(request, body: "", status: 201)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        #expect(await store.report(reason: .spam, details: "  Coin listings \n", account: account))
        #expect(reports.count == 1)
        #expect(reports.first as? [String: String] == [key: subject.id, "reason": "spam", "details": "Coin listings"])
        #expect(store.notice == .reported)
        #expect(store.reportError == nil)
        #expect(!store.isReporting)
        // Details are optional; an empty note is left out rather than sent blank.
        #expect(await store.report(reason: .other, details: "  ", account: account))
        #expect(reports.last as? [String: String] == [key: subject.id, "reason": "other"])
    }

    @Test("A report needs a reason and details the server will keep")
    func reportNeedsAReasonAndDetailsThatFit() async throws {
        var attempts = 0
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/account_reports/organizer" else { return nil }
            attempts += 1
            return HTTPFixture.response(request, body: "", status: 201)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: .huddl("coffee"))
        let tooLong = String(repeating: "a", count: ModerationStore.detailsLimit + 1)
        #expect(!store.canReport(reason: nil, details: "Coin listings"))
        #expect(!store.canReport(reason: .spam, details: tooLong))
        #expect(store.isTooLong(tooLong))
        #expect(store.canReport(reason: .spam, details: String(tooLong.dropLast()) + "  "))
        #expect(store.canReport(reason: .other, details: ""))
        #expect(!(await store.report(reason: nil, details: "Coin listings", account: account)))
        #expect(!(await store.report(reason: .spam, details: tooLong, account: account)))
        #expect(attempts == 0)
        #expect(store.notice == nil)
    }

    @Test("A report that doesn’t go through says why, keeps the person signed in, and can be sent again", arguments: [
        (ModerationSubject.huddl("coffee"), 400, #"{"errors":[{"detail":"Say what's wrong: spam or advertising, or other."}]}"#,
         "Say what's wrong: spam or advertising, or other."),
        (ModerationSubject.group("neighbors"), 400, "not json", confirmEmail),
        (ModerationSubject.huddl("coffee"), 403, #"{"errors":[{"detail":"forbidden"}]}"#, confirmEmail),
        (ModerationSubject.group("neighbors"), 404, "{}", confirmEmail),
        (ModerationSubject.group("neighbors"), 429, "{}", "Too many attempts. Please wait a moment and try again."),
        (ModerationSubject.huddl("coffee"), 503, "{}", couldNotSend),
        (ModerationSubject.group("neighbors"), -1, "", couldNotSend)
    ])
    func failedReportExplainsAndCanRetry(subject: ModerationSubject, status: Int, body: String, message: String) async throws {
        var attempts = 0
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/account_reports/\(subject.route)" else { return nil }
            attempts += 1
            return attempts == 1 ? try reply(request, status: status, body: body) : try reply(request, status: 201, body: "")
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        #expect(!(await store.report(reason: .spam, details: "", account: account)))
        #expect(store.reportError == message)
        #expect(store.notice == nil)
        #expect(!store.isReporting)
        #expect(account.user?.id == "neighbor")
        #expect(await store.report(reason: .spam, details: "", account: account))
        #expect(store.reportError == nil)
        #expect(store.notice == .reported)
        #expect(attempts == 2)
    }

    @Test("A reopened report sheet starts without the last attempt’s error")
    func reopenedReportStartsClean() async throws {
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/account_reports/group" else { return nil }
            return HTTPFixture.response(request, body: "{}", status: 503)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: .group("neighbors"))
        #expect(!(await store.report(reason: .other, details: "", account: account)))
        #expect(store.reportError == Self.couldNotSend)
        store.clearReportError()
        #expect(store.reportError == nil)
    }

    @Test("An expired session while reporting returns the person to signed-out browsing",
          arguments: [ModerationSubject.huddl("coffee"), .group("neighbors")])
    func expiredSessionWhileReporting(subject: ModerationSubject) async throws {
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/account_reports/\(subject.route)" else { return nil }
            return HTTPFixture.response(request, body: "{}", status: 401)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        #expect(!(await store.report(reason: .spam, details: "", account: account)))
        #expect(store.reportError == "Your session has expired. Please sign in again.")
        #expect(store.notice == nil)
        #expect(account.user == nil)
        #expect(try await tokens.load() == nil)
        #expect(await account.browsingToken() == nil)
    }

    // MARK: Blocking

    @Test("A block names the huddl or group and asks lists to drop that person’s huddlz", arguments: [
        (ModerationSubject.huddl("coffee"), "/api/json/blocks/organizer", "huddl_id"),
        (ModerationSubject.group("neighbors"), "/api/json/blocks/group", "group_id")
    ])
    func blockNamesThePageAndRefreshesLists(subject: ModerationSubject, path: String, key: String) async throws {
        var blocks: [[String: Any]] = []
        let (account, tokens) = await signedIn { request in
            guard request.url?.path.hasPrefix("/api/json/blocks") == true else { return nil }
            #expect(request.url?.path == path)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
            blocks.append(try sent(request))
            return HTTPFixture.response(request, body: #"{"data":{"type":"user_block","id":"b1","attributes":{}}}"#, status: 201)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        let before = account.blockRevision
        await store.block(account: account)
        #expect(blocks.count == 1)
        #expect(blocks.first?["type"] as? String == "user_block")
        #expect(blocks.first?["attributes"] as? [String: String] == [key: subject.id])
        #expect(store.notice == .blocked)
        #expect(!store.isBlocking)
        #expect(account.blockRevision != before)
        store.clearNotice()
        #expect(store.notice == nil)
    }

    @Test("A block that doesn’t go through changes no lists and says why", arguments: [
        (ModerationSubject.huddl("coffee"), 400, #"{"errors":[{"detail":"You organize this huddl."}]}"#, "You organize this huddl."),
        (ModerationSubject.group("neighbors"), 400, #"{"errors":[{"detail":"You own this group."}]}"#, "You own this group."),
        (ModerationSubject.group("neighbors"), 400, #"{"errors":[{"detail":"This group is not available."}]}"#, "This group is not available."),
        (ModerationSubject.huddl("coffee"), 422, #"{"errors":[{"detail":"  "}]}"#, "This organizer can’t be blocked."),
        (ModerationSubject.huddl("coffee"), 403, "{}", "This organizer can’t be blocked."),
        (ModerationSubject.group("neighbors"), 404, "{}", "This group’s owner can’t be blocked."),
        (ModerationSubject.huddl("coffee"), 429, "{}", "Too many attempts. Please wait a moment and try again."),
        (ModerationSubject.huddl("coffee"), 503, "{}", "Couldn’t block the organizer. Check your connection and try again."),
        (ModerationSubject.group("neighbors"), -1, "", "Couldn’t block the group’s owner. Check your connection and try again.")
    ])
    func failedBlockExplainsAndKeepsLists(subject: ModerationSubject, status: Int, body: String, message: String) async throws {
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/blocks/\(subject.route)" else { return nil }
            return try reply(request, status: status, body: body)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        let before = account.blockRevision
        await store.block(account: account)
        #expect(store.notice == .failed(message))
        #expect(subject.title(of: .failed(message)) == "Something went wrong")
        #expect(subject.message(of: .failed(message)) == message)
        #expect(!store.isBlocking)
        #expect(account.blockRevision == before)
        #expect(account.user?.id == "neighbor")
    }

    @Test("An expired session while blocking returns the person to signed-out browsing",
          arguments: [ModerationSubject.huddl("coffee"), .group("neighbors")])
    func expiredSessionWhileBlocking(subject: ModerationSubject) async throws {
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/blocks/\(subject.route)" else { return nil }
            return HTTPFixture.response(request, body: "{}", status: 401)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        let before = account.blockRevision
        await store.block(account: account)
        #expect(store.notice == .failed("Your session has expired. Please sign in again."))
        #expect(account.user == nil)
        #expect(try await tokens.load() == nil)
        #expect(account.blockRevision == before)
    }

    @Test("A second tap while a block is on its way sends it once")
    func blockSendsOnce() async throws {
        let pending = PendingHTTPResponse()
        var attempts = 0
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/blocks/group" else { return nil }
            attempts += 1
            return try await pending.fetch(request)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: .group("neighbors"))
        let first = Task { await store.block(account: account) }
        await pending.waitUntilRequested()
        #expect(store.isBlocking)
        await store.block(account: account)
        #expect(attempts == 1)
        #expect(store.notice == nil)
        pending.finish(body: "{}", status: 201)
        await first.value
        #expect(store.notice == .blocked)
        #expect(!store.isBlocking)
    }

    @Test("Each page names who was blocked and who won’t hear about a report")
    func noticesNameTheRightPerson() {
        let huddl = ModerationSubject.huddl("coffee"), group = ModerationSubject.group("neighbors")
        #expect(huddl.title(of: .blocked) == "Organizer blocked")
        #expect(group.title(of: .blocked) == "Group owner blocked")
        #expect(huddl.title(of: .reported) == group.title(of: .reported))
        #expect(huddl.message(of: .reported).hasSuffix("We won’t tell the organizer."))
        #expect(group.message(of: .reported).hasSuffix("We won’t tell the group’s owner."))
    }

    // MARK: Your own huddl or group

    @Test("People get no report or block options on a huddl they organize or a group they own", arguments: [
        (ModerationSubject.huddl("coffee"), "/api/json/huddlz/coffee", "fields[huddl]", "organized_by_me", true),
        (ModerationSubject.huddl("coffee"), "/api/json/huddlz/coffee", "fields[huddl]", "organized_by_me", false),
        (ModerationSubject.group("neighbors"), "/api/json/groups/neighbors", "fields[group]", "owned_by_me", true),
        (ModerationSubject.group("neighbors"), "/api/json/groups/neighbors", "fields[group]", "owned_by_me", false)
    ])
    func ownPagesHideTheOptions(subject: ModerationSubject, path: String, fields: String, attribute: String, own: Bool) async throws {
        var checks = 0
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == path else { return nil }
            #expect(HTTPFixture.parameters(request) == [fields: attribute])
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            checks += 1
            return HTTPFixture.response(request, body: "{\"data\":{\"id\":\"\(subject.id)\",\"attributes\":{\"\(attribute)\":\(own)}}}")
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        #expect(!store.isOwn)
        #expect(!store.showsMenu(for: account.user))
        await store.checkOwnership(account: account)
        #expect(store.isOwn == own)
        #expect(store.showsMenu(for: account.user) == !own)
        #expect(checks == 1)
        // Once they sign out, the page offers the options again and asks the server nothing.
        await account.signOut()
        await store.checkOwnership(account: account)
        #expect(!store.isOwn)
        #expect(store.showsMenu(for: account.user))
        #expect(checks == 1)
    }

    @Test("Owners never flash report or block options while ownership is loading or re-checking")
    func menuWaitsForOwnershipCheck() async throws {
        let firstPending = PendingHTTPResponse()
        let secondPending = PendingHTTPResponse()
        var checks = 0
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/huddlz/coffee" else { return nil }
            checks += 1
            return try await (checks == 1 ? firstPending : secondPending).fetch(request)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: .huddl("coffee"))
        #expect(store.showsMenu(for: nil))
        #expect(!store.showsMenu(for: account.user))
        let check = Task { await store.checkOwnership(account: account) }
        await firstPending.waitUntilRequested()
        #expect(!store.showsMenu(for: account.user))
        firstPending.finish(body: #"{"data":{"id":"coffee","attributes":{"organized_by_me":true}}}"#)
        await check.value
        #expect(store.isOwn)
        #expect(!store.showsMenu(for: account.user))

        // A repeat check for the same confirmed owner keeps the menu hidden until the fresh answer lands.
        let recheck = Task { await store.checkOwnership(account: account) }
        await secondPending.waitUntilRequested()
        #expect(!store.showsMenu(for: account.user))
        secondPending.finish(body: #"{"data":{"id":"coffee","attributes":{"organized_by_me":true}}}"#)
        await recheck.value
        #expect(store.isOwn)
        #expect(!store.showsMenu(for: account.user))
    }

    @Test("When the ownership check fails, the report and block options stay", arguments: [
        (ModerationSubject.huddl("coffee"), 503, "{}"),
        (ModerationSubject.group("neighbors"), 404, "{}"),
        (ModerationSubject.huddl("coffee"), -1, ""),
        (ModerationSubject.group("neighbors"), 200, #"{"data":{"id":"neighbors","attributes":{}}}"#),
        (ModerationSubject.huddl("coffee"), 200, #"{"data":{"id":"another","attributes":{"organized_by_me":true}}}"#)
    ])
    func failedOwnershipCheckKeepsTheOptions(subject: ModerationSubject, status: Int, body: String) async throws {
        let (account, tokens) = await signedIn { request in
            guard request.url?.query()?.contains("_by_me") == true else { return nil }
            return try reply(request, status: status, body: body)
        }
        defer { Task { try? await tokens.clear() } }
        let store = ModerationStore(subject: subject)
        await store.checkOwnership(account: account)
        #expect(!store.isOwn)
        #expect(account.user?.id == "neighbor")
    }

    // MARK: Blocked people

    @Test("Blocked people are listed by name in the server’s order and can be unblocked")
    func listAndUnblock() async throws {
        var deleted: [String] = []
        let (account, tokens) = await signedIn { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/json/blocks"):
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                return HTTPFixture.response(request, body: """
                {"data":[{"type":"user_block","id":"b2","attributes":{"blocked_user_name":"Crypto Kings Promo"}},
                         {"type":"user_block","id":"b1","attributes":{"blocked_user_name":null}}]}
                """)
            case ("DELETE", "/api/json/blocks/b2"):
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                deleted.append("b2")
                return HTTPFixture.response(request, body: "", status: 204)
            default: return nil
            }
        }
        defer { Task { try? await tokens.clear() } }
        let store = BlockedPeopleStore()
        await store.load(account: account)
        #expect(store.people == [BlockedPerson(id: "b2", name: "Crypto Kings Promo"),
                                 BlockedPerson(id: "b1", name: "Someone you blocked")])
        #expect(store.loadedUserID == "neighbor")
        #expect(!store.loadFailed)
        let before = account.blockRevision
        await store.unblock(store.people[0], account: account)
        #expect(deleted == ["b2"])
        #expect(store.people.map(\.id) == ["b1"])
        #expect(store.unblocking == nil)
        #expect(store.errorMessage == nil)
        #expect(account.blockRevision != before)
    }

    @Test("A failed unblock keeps the person listed, says why, and can be tried again", arguments: [503, 429, -1])
    func failedUnblockCanRetry(status: Int) async throws {
        var attempts = 0
        let (account, tokens) = await signedIn { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/json/blocks"):
                return HTTPFixture.response(request, body: #"{"data":[{"id":"b1","attributes":{"blocked_user_name":"Crypto Kings Promo"}}]}"#)
            case ("DELETE", "/api/json/blocks/b1"):
                attempts += 1
                return attempts == 1 ? try reply(request, status: status) : try reply(request, status: 200, body: #"{"data":null}"#)
            default: return nil
            }
        }
        defer { Task { try? await tokens.clear() } }
        let store = BlockedPeopleStore()
        await store.load(account: account)
        let person = try #require(store.people.first)
        let before = account.blockRevision
        await store.unblock(person, account: account)
        #expect(store.people == [person])
        #expect(store.errorMessage == "Couldn’t unblock Crypto Kings Promo. Please try again.")
        #expect(store.unblocking == nil)
        #expect(account.blockRevision == before)
        await store.unblock(person, account: account)
        #expect(store.people.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(account.blockRevision != before)
    }

    @Test("A block already removed on another device leaves the list too")
    func alreadyUnblockedLeavesTheList() async throws {
        let (account, tokens) = await signedIn { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/json/blocks"):
                return HTTPFixture.response(request, body: #"{"data":[{"id":"b1","attributes":{"blocked_user_name":"Crypto Kings Promo"}}]}"#)
            case ("DELETE", "/api/json/blocks/b1"): return HTTPFixture.response(request, body: "{}", status: 404)
            default: return nil
            }
        }
        defer { Task { try? await tokens.clear() } }
        let store = BlockedPeopleStore()
        await store.load(account: account)
        await store.unblock(try #require(store.people.first), account: account)
        #expect(store.people.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test("A blocked list that fails to load can be loaded again", arguments: [503, -1])
    func failedListCanRetry(status: Int) async throws {
        var attempts = 0
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/blocks" else { return nil }
            attempts += 1
            return attempts == 1 ? try reply(request, status: status)
                : try reply(request, status: 200, body: #"{"data":[{"id":"b1","attributes":{"blocked_user_name":"Crypto Kings Promo"}}]}"#)
        }
        defer { Task { try? await tokens.clear() } }
        let store = BlockedPeopleStore()
        await store.load(account: account)
        #expect(store.loadFailed)
        #expect(store.people.isEmpty)
        await store.load(account: account)
        #expect(!store.loadFailed)
        #expect(store.people.map(\.name) == ["Crypto Kings Promo"])
    }

    @Test("An expired session while unblocking returns the person to signed-out browsing")
    func expiredSessionWhileUnblocking() async throws {
        let (account, tokens) = await signedIn { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/json/blocks"):
                return HTTPFixture.response(request, body: #"{"data":[{"id":"b1","attributes":{"blocked_user_name":"Crypto Kings Promo"}}]}"#)
            case ("DELETE", "/api/json/blocks/b1"): return HTTPFixture.response(request, body: "{}", status: 401)
            default: return nil
            }
        }
        defer { Task { try? await tokens.clear() } }
        let store = BlockedPeopleStore()
        await store.load(account: account)
        let before = account.blockRevision
        await store.unblock(try #require(store.people.first), account: account)
        #expect(store.errorMessage == "Your session has expired. Please sign in again.")
        #expect(account.user == nil)
        #expect(try await tokens.load() == nil)
        #expect(account.blockRevision == before)
        // A signed-out person has no blocked list, and none is requested.
        await store.load(account: account)
        #expect(store.people.isEmpty)
        #expect(store.loadedUserID == nil)
        #expect(!store.loadFailed)
    }

    // MARK: Blocked organizers stay out of search and group pages

    @Test("Blocking drops that organizer’s huddlz from search in place, and unblocking brings them back")
    func blockingFiltersSearch() async throws {
        var isBlocked = false
        let (account, tokens) = await signedIn { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/json/blocks/organizer"):
                isBlocked = true
                return HTTPFixture.response(request, body: #"{"data":{"type":"user_block","id":"b1","attributes":{}}}"#, status: 201)
            case ("GET", "/api/json/blocks"):
                return HTTPFixture.response(request, body: isBlocked
                    ? #"{"data":[{"id":"b1","attributes":{"blocked_user_name":"Crypto Kings Promo"}}]}"# : #"{"data":[]}"#)
            case ("DELETE", "/api/json/blocks/b1"):
                isBlocked = false
                return HTTPFixture.response(request, body: "", status: 204)
            default: return nil
            }
        }
        defer { Task { try? await tokens.clear() } }
        // Like the server, the fixture hides a blocked organizer's huddl only from the person who blocked them.
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let asThePerson = request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token"
            let events = isBlocked && asThePerson ? [HTTPFixture.hike] : [HTTPFixture.coffee, HTTPFixture.hike]
            return HTTPFixture.response(request, body: HTTPFixture.page(events))
        })
        let query = DiscoveryQuery()
        await discovery.load(query, token: await account.browsingToken())
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])

        let listsBefore = account.blockRevision
        let moderation = ModerationStore(subject: .huddl("coffee"))
        await moderation.block(account: account)
        #expect(moderation.notice == .blocked)
        #expect(account.blockRevision != listsBefore)
        await discovery.search(query, token: await account.browsingToken())
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        #expect(discovery.errorMessage == nil)

        let blocked = BlockedPeopleStore()
        await blocked.load(account: account)
        await blocked.unblock(try #require(blocked.people.first), account: account)
        await discovery.search(query, token: await account.browsingToken())
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])
    }

    @Test("Signed-in search and its further batches run as the person; a visitor’s carry no session")
    func searchRunsAsThePerson() async throws {
        var authorizations: [String?] = []
        let next = "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=coffee"
        let client = DiscoveryClient { request in
            authorizations.append(request.value(forHTTPHeaderField: "Authorization"))
            if HTTPFixture.parameters(request)["page[after]"] != nil {
                return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
            }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee], next: next))
        }
        let (account, tokens) = await signedIn { _ in nil }
        defer { Task { try? await tokens.clear() } }
        let signedIn = DiscoveryStore(client: client)
        await signedIn.load(DiscoveryQuery(), token: await account.browsingToken())
        await signedIn.loadMore()
        #expect(signedIn.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(authorizations == ["Bearer fixture-token", "Bearer fixture-token"])

        await account.signOut()
        authorizations = []
        let visitor = DiscoveryStore(client: client)
        await visitor.load(DiscoveryQuery(), token: await account.browsingToken())
        await visitor.loadMore()
        #expect(visitor.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(authorizations == [nil, nil])
    }

    @Test("Changing viewer drops previous cards, cursor, and token even when the new search fails")
    func viewerChangeClearsPreviousResultsAndToken() async {
        var authorizations: [String?] = []
        var failVisitor = true
        let next = "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=coffee"
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            authorizations.append(authorization)
            if authorization == "Bearer fixture-token" {
                return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee], next: next))
            }
            if failVisitor { return HTTPFixture.response(request, body: "{}", status: 503) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
        })
        let query = DiscoveryQuery()
        await discovery.load(query, token: "fixture-token")
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
        #expect(discovery.nextPage?.absoluteString == next)

        // Signing out (or account deletion / expiry) drops member cards and cursor before the visitor search finishes.
        await discovery.load(query, token: nil)
        #expect(discovery.huddlz.isEmpty)
        #expect(discovery.nextPage == nil)
        #expect(discovery.errorMessage != nil)
        // Paginating after the failed visitor refresh cannot send the old member's token.
        await discovery.loadMore()
        #expect(authorizations == ["Bearer fixture-token", nil])

        failVisitor = false
        await discovery.load(query, token: nil)
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        #expect(discovery.errorMessage == nil)
        await discovery.load(query, token: nil)
        #expect(authorizations == ["Bearer fixture-token", nil, nil])
    }

    @Test("A block clears pre-block cards and cursor even on failure, and supersedes an in-flight refresh")
    func blockClearsCardsAndSupersedesInFlightRefresh() async {
        let pendingRefresh = PendingHTTPResponse()
        let next = "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=coffee"
        var isBlocked = false
        var failNext = false
        var calls = 0
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            calls += 1
            if calls == 2 { return try await pendingRefresh.fetch(request) }
            if failNext { return HTTPFixture.response(request, body: "{}", status: 503) }
            let events = isBlocked ? [HTTPFixture.hike] : [HTTPFixture.coffee, HTTPFixture.hike]
            return HTTPFixture.response(request, body: HTTPFixture.page(events, next: isBlocked ? nil : next))
        })
        let query = DiscoveryQuery()
        await discovery.load(query, token: "fixture-token")
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(discovery.nextPage?.absoluteString == next)

        let staleRefresh = Task { await discovery.refresh(query, token: "fixture-token") }
        await pendingRefresh.waitUntilRequested()
        isBlocked = true
        failNext = true
        await discovery.search(query, token: "fixture-token")
        pendingRefresh.finish(body: HTTPFixture.page([HTTPFixture.coffee, HTTPFixture.hike]))
        await staleRefresh.value
        // Even if the post-block reload fails, pre-block cards and pagination cursor stay gone.
        #expect(discovery.huddlz.isEmpty)
        #expect(discovery.nextPage == nil)
        #expect(discovery.errorMessage != nil)
        #expect(!discovery.isRefreshing)

        failNext = false
        await discovery.search(query, token: "fixture-token")
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        #expect(discovery.errorMessage == nil)
    }

    @Test("An expired session still searches, as a visitor")
    func expiredSessionStillSearches() async {
        var authorizations: [String?] = []
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            authorizations.append(authorization)
            if authorization != nil { return HTTPFixture.response(request, body: "{}", status: 401) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee]))
        })
        await discovery.load(DiscoveryQuery(), token: "expired")
        #expect(authorizations == ["Bearer expired", nil])
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
        #expect(discovery.errorMessage == nil)
    }

    @Test("A group page lists huddlz as the person, and a block made elsewhere drops that organizer’s huddlz")
    func groupPageFiltersBlockedOrganizers() async {
        var isBlocked = false
        var authorizations: [String?] = []
        let next = "https://huddlz.com/api/json/huddlz/by_group?group_id=neighbors&page%5Bafter%5D=walk"
        let store = GroupDetailStore(id: "neighbors", client: DiscoveryClient { request in
            guard request.url?.path == "/api/json/huddlz/by_group" else {
                return HTTPFixture.response(request, body: Self.group)
            }
            authorizations.append(request.value(forHTTPHeaderField: "Authorization"))
            if HTTPFixture.parameters(request)["page[after]"] != nil {
                return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
            }
            return HTTPFixture.response(request, body: isBlocked
                ? HTTPFixture.page([]) : HTTPFixture.page([HTTPFixture.coffee], next: next))
        })
        await store.load(token: "fixture-token")
        await store.loadMore()
        #expect(store.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(authorizations == ["Bearer fixture-token", "Bearer fixture-token"])
        isBlocked = true
        await store.reloadHuddlz(token: "fixture-token")
        #expect(store.group?.attributes.name == "Juniper Neighbors")
        #expect(store.hasLoadedHuddlz)
        #expect(store.huddlz.isEmpty)
        #expect(store.nextPage == nil)
        #expect(store.huddlzError == nil)
        #expect(authorizations.last == "Bearer fixture-token")
    }

    @Test("A batch that lands after a block can’t put the blocked organizer’s huddlz back on a group page")
    func lateGroupBatchStaysOut() async {
        let pending = PendingHTTPResponse()
        var lists = 0
        let next = "https://huddlz.com/api/json/huddlz/by_group?group_id=neighbors&page%5Bafter%5D=hike"
        let store = GroupDetailStore(id: "neighbors", client: DiscoveryClient { request in
            guard request.url?.path == "/api/json/huddlz/by_group" else {
                return HTTPFixture.response(request, body: Self.group)
            }
            if HTTPFixture.parameters(request)["page[after]"] != nil { return try await pending.fetch(request) }
            lists += 1
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike], next: lists == 1 ? next : nil))
        })
        await store.load(token: "fixture-token")
        let more = Task { await store.loadMore() }
        await pending.waitUntilRequested()
        await store.reloadHuddlz(token: "fixture-token")
        pending.finish(body: HTTPFixture.page([HTTPFixture.coffee]))
        await more.value
        #expect(store.huddlz.map(\.id) == ["hike"])
        #expect(store.nextPage == nil)
        #expect(!store.isLoadingMore)
        #expect(!store.moreError)
    }

    @Test("A group page that fails to reload after a block shows no stale huddlz and can be retried")
    func failedGroupReloadCanRetry() async {
        var lists = 0
        let store = GroupDetailStore(id: "neighbors", client: DiscoveryClient { request in
            guard request.url?.path == "/api/json/huddlz/by_group" else {
                return HTTPFixture.response(request, body: Self.group)
            }
            lists += 1
            if lists == 2 { return HTTPFixture.response(request, body: "{}", status: 503) }
            return HTTPFixture.response(request, body: HTTPFixture.page(lists == 1 ? [HTTPFixture.coffee, HTTPFixture.hike] : [HTTPFixture.hike]))
        })
        await store.load(token: "fixture-token")
        await store.reloadHuddlz(token: "fixture-token")
        #expect(store.huddlz.isEmpty)
        #expect(store.huddlzError != nil)
        await store.load(token: "fixture-token")
        #expect(store.huddlz.map(\.id) == ["hike"])
        #expect(store.huddlzError == nil)
    }

    @Test("An expired session still lists a group’s huddlz, as a visitor")
    func expiredSessionStillListsGroupHuddlz() async {
        var authorizations: [String?] = []
        let store = GroupDetailStore(id: "neighbors", client: DiscoveryClient { request in
            guard request.url?.path == "/api/json/huddlz/by_group" else {
                return HTTPFixture.response(request, body: Self.group)
            }
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            authorizations.append(authorization)
            if authorization != nil { return HTTPFixture.response(request, body: "{}", status: 401) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee]))
        })
        await store.load(token: "expired")
        #expect(authorizations == ["Bearer expired", nil])
        #expect(store.huddlz.map(\.id) == ["coffee"])
        #expect(store.huddlzError == nil)
    }

    @Test("Changing viewer while a group header is loading never fetches its huddlz with the old token")
    func groupViewerChangeDuringHeaderLoadDropsOldToken() async {
        let pendingGroup = PendingHTTPResponse()
        var byGroupAuth: [String?] = []
        let store = GroupDetailStore(id: "neighbors", client: DiscoveryClient { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            if request.url?.path == "/api/json/groups/neighbors" {
                if authorization != nil { return try await pendingGroup.fetch(request) }
                return HTTPFixture.response(request, body: Self.group)
            }
            byGroupAuth.append(authorization)
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.hike]))
        })
        let memberLoad = Task { await store.load(token: "member-token") }
        await pendingGroup.waitUntilRequested()
        await store.reloadHuddlz(token: nil)
        pendingGroup.finish(body: Self.group)
        await memberLoad.value
        #expect(byGroupAuth == [nil])
        #expect(store.group?.attributes.name == "Juniper Neighbors")
        #expect(store.huddlz.map(\.id) == ["hike"])
    }

    @Test("A private group disappears when the member signs out")
    func privateGroupClearsOnSignOut() async {
        let store = GroupDetailStore(id: "neighbors", client: DiscoveryClient { request in
            let isMember = request.value(forHTTPHeaderField: "Authorization") == "Bearer member-token"
            if !isMember { return HTTPFixture.response(request, body: "{}", status: 404) }
            if request.url?.path == "/api/json/groups/neighbors" {
                return HTTPFixture.response(request, body: Self.group)
            }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee]))
        })
        await store.load(token: "member-token")
        #expect(store.group?.attributes.name == "Juniper Neighbors")
        #expect(store.huddlz.map(\.id) == ["coffee"])

        await store.reloadHuddlz(token: nil)
        #expect(store.group == nil)
        #expect(store.huddlz.isEmpty)
        #expect(store.errorMessage == "This group is no longer available.")
    }

    @Test("A member-only huddl opens with the member’s session and disappears when they sign out")
    func memberOnlyHuddlDetailUsesSessionAndClearsOnSignOut() async {
        var authorizations: [String?] = []
        let store = HuddlDetailStore(id: "coffee", client: DiscoveryClient { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            authorizations.append(authorization)
            guard authorization == "Bearer member-token" else {
                return HTTPFixture.response(request, body: "{}", status: 404)
            }
            return HTTPFixture.response(request, body: "{\"data\":\(HTTPFixture.coffee)}")
        })
        await store.load(token: "member-token")
        #expect(store.huddl?.title == "Coffee with neighbors")
        #expect(store.errorMessage == nil)

        await store.load(token: nil)
        #expect(store.huddl == nil)
        #expect(store.errorMessage == "This huddl is no longer available.")
        #expect(authorizations == ["Bearer member-token", nil])
    }

    @Test("Signing in on a public huddl keeps it on screen while reloading so sign-up stays open")
    func signingInKeepsPublicHuddlWhileReloading() async {
        let pending = PendingHTTPResponse()
        let store = HuddlDetailStore(id: "coffee", client: DiscoveryClient { request in
            if request.value(forHTTPHeaderField: "Authorization") != nil {
                return try await pending.fetch(request)
            }
            return HTTPFixture.response(request, body: "{\"data\":\(HTTPFixture.coffee)}")
        })
        await store.load(token: nil)
        #expect(store.huddl?.title == "Coffee with neighbors")

        let reload = Task { await store.load(token: "member-token") }
        await pending.waitUntilRequested()
        // Keeping the public huddl mounted avoids tearing down the RSVP sign-up sheet mid-flow.
        #expect(store.huddl?.title == "Coffee with neighbors")
        #expect(store.errorMessage == nil)
        pending.finish(body: "{\"data\":\(HTTPFixture.coffee)}")
        await reload.value
        #expect(store.huddl?.title == "Coffee with neighbors")
        #expect(store.errorMessage == nil)
    }

    @Test("A transient reload failure keeps a loaded huddl on screen, while a 404 clears it")
    func transientDetailReloadErrorKeepsHuddl() async {
        var responses = [(200, "{\"data\":\(HTTPFixture.coffee)}"), (503, "{}"), (404, "{}")]
        let store = HuddlDetailStore(id: "coffee", client: DiscoveryClient { request in
            let next = responses.removeFirst()
            return HTTPFixture.response(request, body: next.1, status: next.0)
        })
        await store.load(token: "member-token")
        #expect(store.huddl?.title == "Coffee with neighbors")

        await store.load(token: "member-token")
        #expect(store.huddl?.title == "Coffee with neighbors")
        #expect(store.errorMessage == nil)

        await store.load(token: "member-token")
        #expect(store.huddl == nil)
        #expect(store.errorMessage == "This huddl is no longer available.")
    }

    @Test("A 403 or a 401 whose visitor retry fails clears cached member-only huddl details", arguments: [
        [403],
        [401, 503]
    ])
    func revokedAccessClearsMemberHuddlDetail(reloadStatuses: [Int]) async {
        var statuses = [200] + reloadStatuses
        let store = HuddlDetailStore(id: "coffee", client: DiscoveryClient { request in
            let status = statuses.removeFirst()
            return HTTPFixture.response(request, body: status == 200 ? "{\"data\":\(HTTPFixture.coffee)}" : "{}", status: status)
        })
        await store.load(token: "member-token")
        #expect(store.huddl?.title == "Coffee with neighbors")

        await store.load(token: "member-token")
        #expect(store.huddl == nil)
        #expect(store.errorMessage == "Huddlz couldn’t load right now. Please try again.")
        #expect(statuses.isEmpty)
    }

    @Test("A cached group load does not interrupt an in-flight next batch")
    func cachedGroupLoadPreservesInFlightLoadMore() async {
        let pendingMore = PendingHTTPResponse()
        let next = "https://huddlz.com/api/json/huddlz/by_group?group_id=neighbors&page%5Bafter%5D=coffee"
        let store = GroupDetailStore(id: "neighbors", client: DiscoveryClient { request in
            if request.url?.path == "/api/json/groups/neighbors" {
                return HTTPFixture.response(request, body: Self.group)
            }
            if HTTPFixture.parameters(request)["page[after]"] != nil {
                return try await pendingMore.fetch(request)
            }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee], next: next))
        })
        await store.load(token: "member-token")
        let more = Task { await store.loadMore() }
        await pendingMore.waitUntilRequested()
        #expect(store.isLoadingMore)
        // Re-running load for the same viewer is a cache hit and leaves page two intact.
        await store.load(token: "member-token")
        pendingMore.finish(body: HTTPFixture.page([HTTPFixture.hike]))
        await more.value
        #expect(store.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(!store.isLoadingMore)
        #expect(store.nextPage == nil)
    }

    @Test("Authenticated discovery refuses HTTP redirects so bearer tokens never leave the API origin")
    func discoveryUsesNoRedirectPolicy() async throws {
        let server = try LocalRedirectServer()
        defer { server.stop() }
        let client = DiscoveryClient(baseURL: server.baseURL)
        await #expect {
            try await client.search(DiscoveryQuery(), token: "secret-token")
        } throws: { error in
            if case DiscoveryError.unavailable = error { return true }
            return false
        }
        #expect(server.paths == ["/api/json/huddlz"])
    }

    // MARK: Searching once, as the right person

    @Test("The first search can wait for the saved session check, however it ends", arguments: [200, 401, 503, -1, 0])
    func savedSessionIsCheckedBeforeSearching(status: Int) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        // Zero stands for a person with no saved session at all.
        if status != 0 { try await tokens.save("fixture-token") }
        let account = AccountStore(client: AccountClient { request in
            try reply(request, status: status, body: "{\"user\":\(Self.user)}")
        }, tokens: tokens)
        #expect(!account.hasCheckedSession)
        #expect(await account.browsingToken() == nil)
        await account.restore()
        #expect(account.hasCheckedSession)
        #expect(await account.browsingToken() == (status == 200 ? "fixture-token" : nil))
    }
}

/// Minimal loopback HTTP server that answers every request with a 302 redirect and records requested paths.
private final class LocalRedirectServer: @unchecked Sendable {
    let baseURL: URL
    private let listenFD: Int32
    private let lock = NSLock()
    private var recordedPaths: [String] = []
    private var stopped = false

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        let port = Int(UInt16(bigEndian: assigned.sin_port))
        self.listenFD = fd
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.serve() }
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        shutdown(listenFD, SHUT_RDWR)
        close(listenFD)
    }

    private func serve() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                lock.lock()
                let isStopped = stopped
                lock.unlock()
                if isStopped { return }
                continue
            }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(client, &buffer, buffer.count)
            if count > 0, let request = String(bytes: buffer[..<count], encoding: .utf8),
               let firstLine = request.split(separator: "\r\n").first {
                let parts = firstLine.split(separator: " ")
                if parts.count >= 2 {
                    let path = String(parts[1].split(separator: "?").first ?? "")
                    lock.lock()
                    recordedPaths.append(path)
                    lock.unlock()
                }
            }
            let reply = "HTTP/1.1 302 Found\r\nLocation: \(baseURL.absoluteString)/redirected\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            _ = reply.withCString { write(client, $0, strlen($0)) }
            close(client)
        }
    }
}
