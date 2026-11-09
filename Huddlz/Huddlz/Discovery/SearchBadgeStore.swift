import Foundation
import Observation

@MainActor
@Observable
final class SearchBadgeStore {
    private var states: [String: AttendanceState] = [:]
    private var userID: String?
    private var revision = UUID()

    func attendance(for id: String, userID: String?) -> AttendanceState? {
        guard let userID, userID == self.userID else { return nil }
        return states[id]
    }

    func clear() {
        revision = UUID()
        states = [:]
        userID = nil
    }

    func load(huddlIDs: Set<String>, account: AccountStore) async {
        clear()
        let request = revision
        guard let userID = account.user?.id, !huddlIDs.isEmpty else { return }
        guard let states = try? await account.attendances(huddlIDs: huddlIDs),
              request == revision, !Task.isCancelled else { return }
        self.states = states
        self.userID = userID
    }
}
