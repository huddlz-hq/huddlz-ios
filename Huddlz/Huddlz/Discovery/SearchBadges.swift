import SwiftUI
import Observation

struct SearchBadgeCard: View {
    let huddl: Huddl
    let store: SearchBadgeStore
    @Environment(AccountStore.self) private var account

    var body: some View {
        HuddlCard(huddl: huddl, attendance: store.attendance(for: huddl.id, userID: account.user?.id))
    }
}

struct SearchBadgeLoader: View {
    let store: SearchBadgeStore
    let huddlIDs: Set<String>
    let refresh: UUID
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: RequestID(userID: account.user?.id, huddlIDs: huddlIDs, phase: phase, refresh: refresh, attendanceRevision: account.attendanceRevision)) {
                store.clear()
                guard phase == .active, account.user != nil, !huddlIDs.isEmpty else { return }
                // Combine visibility updates during scrolling into one request.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await store.load(huddlIDs: huddlIDs, account: account)
            }
    }

    private struct RequestID: Equatable {
        let userID: String?
        let huddlIDs: Set<String>
        let phase: ScenePhase
        let refresh: UUID
        let attendanceRevision: UUID
    }
}
