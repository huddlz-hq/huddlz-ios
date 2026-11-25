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
    /// The session the group and cards on screen were fetched with; further batches use the same one.
    private var loadedGroupToken: String?
    private var loadedToken: String?

    init(id: String, client: DiscoveryClient? = nil) {
        self.id = id
        self.client = client ?? DiscoveryClient()
    }

    /// Pass the session token to load as the signed-in person, so private groups load and blocked organizers stay out.
    func load(token: String? = nil) async {
        let request = UUID()
        revision = request
        if group != nil, loadedGroupToken != token {
            clearForViewerChange()
        }
        if group == nil {
            errorMessage = nil
            do {
                let result = try await client.group(id: id, token: token)
                guard !Task.isCancelled, request == revision else { return }
                group = result
                loadedGroupToken = token
            } catch {
                guard !Task.isCancelled, request == revision else { return }
                if case DiscoveryError.notFound = error {
                    errorMessage = "This group is no longer available."
                } else {
                    errorMessage = "The group couldn’t load right now. Please try again."
                }
                return
            }
        }
        guard !hasLoadedHuddlz || loadedToken != token else { return }
        if loadedToken != token {
            huddlz = []
            nextPage = nil
            moreError = false
            isLoadingMore = false
            hasLoadedHuddlz = false
            loadedToken = nil
        }
        huddlzError = nil
        do {
            let page = try await client.groupHuddlz(id: id, token: token)
            guard !Task.isCancelled, request == revision else { return }
            huddlz = page.huddlz
            nextPage = page.next
            loadedToken = token
            hasLoadedHuddlz = true
        } catch {
            guard !Task.isCancelled, request == revision else { return }
            huddlzError = "Please try again."
        }
    }

    /// Fetches again after a block or unblock, or once someone signs in or out.
    func reloadHuddlz(token: String? = nil) async {
        if group != nil, loadedGroupToken != token {
            clearForViewerChange()
        } else {
            hasLoadedHuddlz = false
            huddlz = []
            nextPage = nil
            moreError = false
            isLoadingMore = false
            huddlzError = nil
            loadedToken = nil
        }
        await load(token: token)
    }

    private func clearForViewerChange() {
        group = nil
        loadedGroupToken = nil
        errorMessage = nil
        hasLoadedHuddlz = false
        huddlz = []
        nextPage = nil
        moreError = false
        isLoadingMore = false
        huddlzError = nil
        loadedToken = nil
    }

    func loadMore() async {
        guard !isLoadingMore, let url = nextPage else { return }
        let request = revision
        isLoadingMore = true
        moreError = false
        defer { if request == revision { isLoadingMore = false } }
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
