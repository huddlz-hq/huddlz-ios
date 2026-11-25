import Foundation
import Observation

@MainActor
@Observable
final class DiscoveryStore {
    private(set) var huddlz: [Huddl] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var refreshError: String?
    private(set) var isLoadingMore = false
    private(set) var moreError: String?
    private(set) var nextPage: URL?

    private let client: DiscoveryClient
    private var revision = UUID()
    private var loadedQuery: DiscoveryQuery?
    /// The session the cards on screen were fetched with; further batches use the same one.
    private var loadedToken: String?

    init(client: DiscoveryClient? = nil) { self.client = client ?? DiscoveryClient() }

    /// Pass the session token to search as the signed-in person, or nil to search as a visitor.
    func load(_ query: DiscoveryQuery, token: String? = nil) async {
        guard loadedQuery != query || loadedToken != token else { return }
        // A new query or viewer drops the previous results, cursor, and token immediately.
        await search(query, token: token)
    }

    func search(_ query: DiscoveryQuery, token: String? = nil) async {
        let request = UUID()
        revision = request
        loadedQuery = nil
        loadedToken = nil
        isLoading = true
        isRefreshing = false
        isLoadingMore = false
        huddlz = []
        nextPage = nil
        errorMessage = nil
        refreshError = nil
        moreError = nil
        defer { if request == revision { isLoading = false } }
        do {
            let page = try await client.search(query, token: token)
            guard request == revision, !Task.isCancelled else { return }
            huddlz = page.huddlz
            nextPage = page.next
            loadedQuery = query
            loadedToken = token
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refresh(_ query: DiscoveryQuery, token: String? = nil, superseding: Bool = false) async {
        if loadedToken != token {
            await search(query, token: token)
            return
        }
        if superseding {
            if loadedQuery != query || isLoading {
                await search(query, token: token)
                return
            }
        } else {
            guard !isLoading, !isRefreshing else { return }
        }
        let request = UUID()
        revision = request
        isRefreshing = true
        isLoadingMore = false
        defer { if request == revision { isRefreshing = false } }
        do {
            let page = try await client.search(query, token: token)
            guard request == revision, !Task.isCancelled else { return }
            huddlz = page.huddlz
            nextPage = page.next
            loadedQuery = query
            loadedToken = token
            errorMessage = nil
            refreshError = nil
            moreError = nil
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            refreshError = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, !isRefreshing, !isLoadingMore, let url = nextPage else { return }
        let request = revision
        isLoadingMore = true
        moreError = nil
        defer { if request == revision { isLoadingMore = false } }
        do {
            let page = try await client.page(at: url, token: loadedToken)
            guard request == revision, !Task.isCancelled else { return }
            var ids = Set(huddlz.map(\.id))
            huddlz.append(contentsOf: page.huddlz.filter { ids.insert($0.id).inserted })
            nextPage = page.next == url ? nil : page.next
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            moreError = error.localizedDescription
        }
    }
}
