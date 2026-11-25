import Foundation
import Observation

/// The people the signed-in person has blocked; responses for a previous account never apply.
@MainActor
@Observable
final class BlockedPeopleStore {
    private(set) var people: [BlockedPerson] = []
    private(set) var loadedUserID: String?
    private(set) var loadFailed = false
    private(set) var unblocking: BlockedPerson.ID?
    private(set) var errorMessage: String?
    private var revision = UUID()

    func load(account: AccountStore) async {
        let request = UUID()
        revision = request
        people = []
        loadedUserID = nil
        loadFailed = false
        errorMessage = nil
        guard let userID = account.user?.id else { return }
        do {
            let result = try await account.blockedPeople()
            guard request == revision, !Task.isCancelled else { return }
            people = result
            loadedUserID = userID
        } catch is CancellationError {
            return
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            loadFailed = true
        }
    }

    func unblock(_ person: BlockedPerson, account: AccountStore) async {
        guard unblocking == nil else { return }
        let request = revision
        unblocking = person.id
        errorMessage = nil
        defer { unblocking = nil }
        do {
            try await account.unblock(person)
            guard request == revision else { return }
            people.removeAll { $0.id == person.id }
        } catch is CancellationError {
            return
        } catch AccountError.unauthorized {
            errorMessage = ModerationStore.sessionExpired
        } catch {
            errorMessage = "Couldn’t unblock \(person.name). Please try again."
        }
    }
}
