import Foundation
import Observation

/// Loads a huddl's details as the current viewer and drops member-only details when the viewer changes.
@MainActor
@Observable
final class HuddlDetailStore {
    let id: Huddl.ID
    private(set) var huddl: Huddl?
    private(set) var errorMessage: String?
    private let client: DiscoveryClient
    private var revision = UUID()
    private var loadedToken: String?

    init(id: Huddl.ID, client: DiscoveryClient? = nil) {
        self.id = id
        self.client = client ?? DiscoveryClient()
    }

    func load(token: String? = nil) async {
        let request = UUID()
        revision = request
        // Drop member-only details as soon as a signed-in viewer leaves, but keep a public huddl on screen while a visitor signs in.
        if loadedToken != nil, loadedToken != token {
            huddl = nil
            loadedToken = nil
        }
        errorMessage = nil
        do {
            let result = try await client.detail(id: id, token: token)
            guard !Task.isCancelled, request == revision else { return }
            huddl = result
            loadedToken = token
        } catch {
            guard !Task.isCancelled, request == revision else { return }
            let accessRevoked: Bool
            switch error {
            case DiscoveryError.notFound, DiscoveryError.forbidden: accessRevoked = true
            default: accessRevoked = false
            }
            if huddl == nil || accessRevoked {
                huddl = nil
                loadedToken = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}
