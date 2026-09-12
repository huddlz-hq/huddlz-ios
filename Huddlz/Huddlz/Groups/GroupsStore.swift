import Foundation
import Observation

/// Holds the signed-in member's groups; responses for a previous account never apply.
@MainActor
@Observable
final class GroupsStore {
    private(set) var groups: [HostingGroup] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    private(set) var loadedUserID: String?
    private(set) var nextPage: URL?
    private(set) var isLoadingMore = false
    private(set) var moreFailed = false
    private var revision = UUID()

    func clear() {
        revision = UUID()
        groups = []
        nextPage = nil
        loadedUserID = nil
        isLoading = false
        loadFailed = false
        isLoadingMore = false
        moreFailed = false
    }

    func load(account: AccountStore) async {
        clear()
        guard let userID = account.user?.id else { return }
        let request = revision
        isLoading = true
        defer { if request == revision { isLoading = false } }
        do {
            let page = try await account.groups()
            guard request == revision, !Task.isCancelled else { return }
            groups = page.groups
            nextPage = page.next
            loadedUserID = userID
        } catch is CancellationError {
            return
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            loadFailed = true
            loadedUserID = userID
        }
    }

    func loadMore(account: AccountStore) async {
        guard let next = nextPage, !isLoading, !isLoadingMore else { return }
        let request = revision
        isLoadingMore = true
        moreFailed = false
        defer { if request == revision { isLoadingMore = false } }
        do {
            let page = try await account.groupsPage(at: next)
            guard request == revision, !Task.isCancelled else { return }
            let known = Set(groups.map(\.id))
            groups += page.groups.filter { !known.contains($0.id) }
            nextPage = page.next
        } catch is CancellationError {
            return
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            moreFailed = true
        }
    }
}
