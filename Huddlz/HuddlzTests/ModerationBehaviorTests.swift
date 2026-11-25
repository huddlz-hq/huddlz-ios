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
        await store.checkOwnership(account: account)
        #expect(store.isOwn == own)
        #expect(checks == 1)
        // Once they sign out, the page offers the options again and asks the server nothing.
        await account.signOut()
        await store.checkOwnership(account: account)
        #expect(!store.isOwn)
        #expect(checks == 1)
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
        await discovery.refresh(query, token: await account.browsingToken())
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        #expect(discovery.refreshError == nil)

        let blocked = BlockedPeopleStore()
        await blocked.load(account: account)
        await blocked.unblock(try #require(blocked.people.first), account: account)
        await discovery.refresh(query, token: await account.browsingToken())
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

    @Test("Signing in re-runs the same search as that person and keeps the cards until it lands")
    func signingInRerunsTheSearchInPlace() async {
        let pending = PendingHTTPResponse()
        var searches = 0
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            searches += 1
            if request.value(forHTTPHeaderField: "Authorization") != nil { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee, HTTPFixture.hike]))
        })
        let query = DiscoveryQuery()
        await discovery.load(query)
        await discovery.load(query)
        #expect(searches == 1)
        let rerun = Task { await discovery.load(query, token: "fixture-token") }
        await pending.waitUntilRequested()
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(!discovery.isLoading)
        #expect(discovery.isRefreshing)
        pending.finish(body: HTTPFixture.page([HTTPFixture.hike]))
        await rerun.value
        #expect(discovery.huddlz.map(\.id) == ["hike"])
        await discovery.load(query, token: "fixture-token")
        #expect(searches == 2)
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
