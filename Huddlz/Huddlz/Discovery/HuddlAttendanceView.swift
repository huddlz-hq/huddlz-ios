import SwiftUI

enum AttendanceState: String, Decodable {
    case confirmed, waitlisted, none

    var title: String {
        switch self {
        case .confirmed: "You’re going"
        case .waitlisted: "You’re on the waitlist"
        case .none: "You haven’t RSVP’d"
        }
    }

    var symbol: String {
        switch self {
        case .confirmed: "checkmark.circle.fill"
        case .waitlisted: "clock"
        case .none: "calendar.badge.questionmark"
        }
    }
}

struct HuddlAttendanceView: View {
    let id: String
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @State private var attendance: AttendanceState?
    @State private var loadedUserID: String?
    @State private var loadFailed = false
    @State private var retry = UUID()

    var body: some View {
        Group {
            if let user = account.user {
                if loadedUserID == user.id, let attendance {
                    Label(attendance.title, systemImage: attendance.symbol)
                        .font(.headline)
                        .foregroundStyle(HuddlStyle.accent)
                } else if loadedUserID == user.id, loadFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn’t check your RSVP.").foregroundStyle(.secondary)
                        Button("Try checking RSVP again") { retry = UUID() }.buttonStyle(.bordered)
                    }
                } else {
                    ProgressView("Checking your RSVP…")
                }
            }
        }
        .task(id: RequestID(userID: account.user?.id, phase: scenePhase, retry: retry)) {
            attendance = nil
            loadFailed = false
            loadedUserID = nil
            guard scenePhase == .active, let userID = account.user?.id else { return }
            do {
                let result = try await account.attendance(huddlID: id)
                guard !Task.isCancelled else { return }
                attendance = result
                loadedUserID = userID
            } catch {
                guard !Task.isCancelled else { return }
                loadFailed = true
                loadedUserID = userID
            }
        }
    }

    private struct RequestID: Equatable {
        let userID: String?
        let phase: ScenePhase
        let retry: UUID
    }

}
