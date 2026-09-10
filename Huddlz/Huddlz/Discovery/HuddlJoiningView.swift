import SwiftUI

struct HuddlJoiningView: View {
    let id: String
    @Environment(AccountStore.self) private var account
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var link: URL?
    @State private var loadedUserID: String?
    @State private var failed = false
    @State private var retry = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join online").font(.title2.bold())
            if let link, let user = account.user, loadedUserID == user.id {
                Button { openURL(link) } label: {
                    Label("Join online", systemImage: "video")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else if let user = account.user, loadedUserID == user.id, failed {
                Text("Couldn’t load joining details.").foregroundStyle(.secondary)
                Button("Try loading joining details again") { retry = UUID() }
                    .buttonStyle(.bordered)
            } else if let user = account.user, loadedUserID != user.id {
                ProgressView("Loading joining details…")
            } else if account.user != nil {
                Text("Online joining details aren’t available for this account yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Online joining details are shared with confirmed attendees and group organizers.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .task(id: RequestID(id: id, userID: account.user?.id, phase: phase, retry: retry, attendanceRevision: account.attendanceRevision)) {
            link = nil
            loadedUserID = nil
            failed = false
            guard phase == .active, let userID = account.user?.id else { return }
            do {
                let result = try await account.joiningLink(huddlID: id)
                guard !Task.isCancelled else { return }
                link = result
                loadedUserID = userID
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
                loadedUserID = userID
            }
        }
    }

    private struct RequestID: Equatable {
        let id: String
        let userID: String?
        let phase: ScenePhase
        let retry: UUID
        let attendanceRevision: UUID
    }
}
