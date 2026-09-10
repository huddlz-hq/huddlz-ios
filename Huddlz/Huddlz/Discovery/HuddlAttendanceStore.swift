import Foundation
import Observation

@MainActor
@Observable
final class HuddlAttendanceStore {
    private(set) var attendance: AttendanceState?
    private(set) var loadedUserID: String?
    private(set) var loadFailed = false
    private(set) var isChanging = false
    private(set) var actionError: String?
    private var readRevision = UUID()

    func clear() {
        readRevision = UUID()
        attendance = nil
        loadedUserID = nil
        loadFailed = false
    }

    func load(huddlID: String, account: AccountStore) async {
        clear()
        let request = readRevision
        guard let userID = account.user?.id else { return }
        do {
            let result = try await account.attendance(huddlID: huddlID)
            guard !Task.isCancelled, request == readRevision else { return }
            attendance = result
            loadedUserID = userID
        } catch {
            guard !Task.isCancelled, request == readRevision else { return }
            loadFailed = true
            loadedUserID = userID
        }
    }

    func change(huddlID: String, action: RSVPAction, account: AccountStore) async {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false }
        actionError = nil
        do {
            let result = try await account.changeAttendance(huddlID: huddlID, action: action)
            readRevision = UUID()
            attendance = result
            loadedUserID = account.user?.id
        } catch is CancellationError {
            return
        } catch let error as RSVPError {
            actionError = error.message
        } catch {
            actionError = "Couldn’t update your RSVP. Please try again."
        }
    }
}
