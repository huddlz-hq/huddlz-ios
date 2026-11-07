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

    init(id: String, client: DiscoveryClient? = nil) {
        self.id = id
        self.client = client ?? DiscoveryClient()
    }

    func load() async {
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
        huddlzError = nil
        do {
            let page = try await client.groupHuddlz(id: id)
            try Task.checkCancellation()
            huddlz = page.huddlz
            nextPage = page.next
            hasLoadedHuddlz = true
        } catch {
            guard !Task.isCancelled else { return }
            huddlzError = "Please try again."
        }
    }

    func loadMore() async {
        guard !isLoadingMore, let url = nextPage else { return }
        isLoadingMore = true
        moreError = false
        defer { isLoadingMore = false }
        do {
            let page = try await client.groupPage(at: url, id: id)
            try Task.checkCancellation()
            var ids = Set(huddlz.map(\.id))
            huddlz.append(contentsOf: page.huddlz.filter { ids.insert($0.id).inserted })
            nextPage = page.next == url ? nil : page.next
        } catch {
            guard !Task.isCancelled else { return }
            moreError = true
        }
    }
}
