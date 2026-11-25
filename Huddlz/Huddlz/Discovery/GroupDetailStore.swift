import Foundation
import Observation

/// Loads a group and its upcoming huddlz; each part can fail and be retried on its own.
@MainActor
@Observable
final class GroupDetailStore {
    let id: String
    private(set) var group: HostingGroup?
    private(set) var huddlz: [Huddl] = []
    private(set) var hasLoadedHuddlz = false
    private(set) var huddlzError: String?
    private(set) var errorMessage: String?
    private(set) var nextPage: URL?
    private(set) var isLoadingMore = false
    private(set) var moreError = false
    private let client: DiscoveryClient
    private var revision = UUID()
    /// The session the cards on screen were fetched with; further batches use the same one.
    private var loadedToken: String?

    init(id: String, client: DiscoveryClient? = nil) {
        self.id = id
        self.client = client ?? DiscoveryClient()
    }

    /// Pass the session token to load as the signed-in person, so huddlz from organizers they blocked stay out.
    func load(token: String? = nil) async {
        if group == nil {
            errorMessage = nil
            do {
                let result = try await client.group(id: id)
                try Task.checkCancellation()
                group = result
            } catch {
                guard !Task.isCancelled else { return }
                if case DiscoveryError.notFound = error {
                    errorMessage = "This group is no longer available."
                } else {
                    errorMessage = "The group couldn’t load right now. Please try again."
                }
                return
            }
        }
        guard !hasLoadedHuddlz else { return }
        let request = UUID()
        revision = request
        huddlzError = nil
        do {
            let page = try await client.groupHuddlz(id: id, token: token)
            try Task.checkCancellation()
            guard request == revision else { return }
            huddlz = page.huddlz
            nextPage = page.next
            loadedToken = token
            hasLoadedHuddlz = true
        } catch {
            guard !Task.isCancelled, request == revision else { return }
            huddlzError = "Please try again."
        }
    }

    /// Fetches the huddlz again after a block or unblock, or once someone signs in or out.
    func reloadHuddlz(token: String? = nil) async {
        revision = UUID()
        hasLoadedHuddlz = false
        huddlz = []
        nextPage = nil
        moreError = false
        // Until the group itself has loaded, its own load fetches the huddlz.
        guard group != nil else { return }
        await load(token: token)
    }

    func loadMore() async {
        guard !isLoadingMore, let url = nextPage else { return }
        let request = revision
        isLoadingMore = true
        moreError = false
        defer { isLoadingMore = false }
        do {
            let page = try await client.groupPage(at: url, id: id, token: loadedToken)
            try Task.checkCancellation()
            guard request == revision else { return }
            var ids = Set(huddlz.map(\.id))
            huddlz.append(contentsOf: page.huddlz.filter { ids.insert($0.id).inserted })
            nextPage = page.next == url ? nil : page.next
        } catch {
            guard !Task.isCancelled, request == revision else { return }
            moreError = true
        }
    }
}
