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

    init(client: DiscoveryClient? = nil) { self.client = client ?? DiscoveryClient() }

    func search(_ query: DiscoveryQuery) async {
        let request = UUID()
        revision = request
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
            let page = try await client.search(query)
            guard request == revision, !Task.isCancelled else { return }
            huddlz = page.huddlz
            nextPage = page.next
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refresh(_ query: DiscoveryQuery) async {
        guard !isLoading, !isRefreshing else { return }
        let request = UUID()
        revision = request
        isRefreshing = true
        isLoadingMore = false
        defer { if request == revision { isRefreshing = false } }
        do {
            let page = try await client.search(query)
            guard request == revision, !Task.isCancelled else { return }
            huddlz = page.huddlz
            nextPage = page.next
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
            let page = try await client.page(at: url)
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
