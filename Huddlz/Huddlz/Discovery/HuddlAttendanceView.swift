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
                    // The RSVP row: state on the left, the one action on the right; it stacks at large text sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            state(attendance)
                            Spacer(minLength: 8)
                            action(for: attendance)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            state(attendance)
                            action(for: attendance)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .surfaceCard()
                } else if status.loadedUserID == user.id, status.loadFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn’t check your RSVP.").foregroundStyle(.secondary)
                        Button("Try checking RSVP again") { retry = UUID() }.buttonStyle(.glass)
                    }
                } else {
                    ProgressView("Checking your RSVP…")
                }
            } else if !acceptsChanges {
                Text("RSVPs are closed for this huddl.").foregroundStyle(.secondary)
            } else {
                Button { showsAccount = true } label: {
                    Text("Sign in to RSVP").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent)
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

    private func state(_ attendance: AttendanceState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: attendance.symbol)
                .font(.title2)
                .foregroundStyle(HuddlStyle.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(attendance.title).font(.headline)
                if status.isChanging {
                    ProgressView("Updating RSVP…").font(.footnote).controlSize(.small)
                } else if !acceptsChanges {
                    Text("RSVPs are closed for this huddl.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func action(for attendance: AttendanceState) -> some View {
        if acceptsChanges {
            if attendance == .none {
                Button("RSVP") { change(.reserve) }
                    .buttonStyle(.glassProminent)
                    .disabled(status.isChanging)
            } else {
                Button(attendance == .waitlisted ? "Leave waitlist" : "Cancel RSVP") { change(.cancel) }
                    .buttonStyle(.glass)
                    .disabled(status.isChanging)
            }
        }
    }

    private func change(_ action: RSVPAction) {
        guard acceptsChanges else { return }
        Task { await status.change(huddlID: id, action: action, account: account) }
    }

    private var acceptsChanges: Bool { lifecycleState == "published" && endsAt > Date.now }

    private struct RequestID: Equatable {
        let userID: String?
        let phase: ScenePhase
        let retry: UUID
    }

}
