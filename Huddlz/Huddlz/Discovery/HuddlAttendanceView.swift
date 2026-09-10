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
    let lifecycleState: String
    let endsAt: Date
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = HuddlAttendanceStore()
    @State private var retry = UUID()
    @State private var showsAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let user = account.user {
                if status.loadedUserID == user.id, let attendance = status.attendance {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(attendance.title, systemImage: attendance.symbol)
                            .font(.headline)
                            .foregroundStyle(HuddlStyle.accent)
                        if acceptsChanges {
                            Button(attendance == .none ? "RSVP" : (attendance == .waitlisted ? "Leave waitlist" : "Cancel RSVP")) {
                                guard acceptsChanges else { return }
                                Task { await status.change(huddlID: id, action: attendance == .none ? .reserve : .cancel, account: account) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(status.isChanging)
                        } else {
                            Text("RSVPs are closed for this huddl.").foregroundStyle(.secondary)
                        }
                        if status.isChanging { ProgressView("Updating RSVP…") }
                    }
                } else if status.loadedUserID == user.id, status.loadFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn’t check your RSVP.").foregroundStyle(.secondary)
                        Button("Try checking RSVP again") { retry = UUID() }.buttonStyle(.bordered)
                    }
                } else {
                    ProgressView("Checking your RSVP…")
                }
            } else if !acceptsChanges {
                Text("RSVPs are closed for this huddl.").foregroundStyle(.secondary)
            } else {
                Button("Sign in to RSVP") { showsAccount = true }.buttonStyle(.borderedProminent)
            }
            if let actionError = status.actionError { Text(actionError).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $showsAccount) { AccountView() }
        .task(id: RequestID(userID: account.user?.id, phase: scenePhase, retry: retry)) {
            if scenePhase == .active {
                await status.load(huddlID: id, account: account)
            } else {
                status.clear()
            }
        }
    }

    private var acceptsChanges: Bool { lifecycleState == "published" && endsAt > Date.now }

    private struct RequestID: Equatable {
        let userID: String?
        let phase: ScenePhase
        let retry: UUID
    }

}
