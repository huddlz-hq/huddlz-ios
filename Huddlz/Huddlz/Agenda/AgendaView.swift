import SwiftUI

struct AgendaView: View {
    var body: some View {
        NavigationStack {
            SignedInContent(title: "Sign in to see your agenda", symbol: "calendar",
                            description: "Your RSVPs and waitlists, by date.") {
                AgendaList()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HuddlStyle.background)
            .navigationTitle("Agenda")
        }
    }
}

private struct AgendaList: View {
    @Environment(AccountStore.self) private var account
    @State private var store = AgendaStore()
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.isLoading {
                    ProgressView("Loading your agenda…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if store.loadFailed {
                    ContentUnavailableView {
                        Label("Couldn’t load your agenda", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try loading your agenda again") { retry = UUID() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if store.loadedUserID != nil, store.days.isEmpty {
                    ContentUnavailableView("Nothing on your agenda", systemImage: "calendar",
                                           description: Text("RSVP to a huddl in Discover and it will show up here."))
                } else {
                    ForEach(store.days) { day in
                        Text(day.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(day.entries) { entry in
                            NavigationLink { HuddlDetailView(id: entry.id) } label: { AgendaRow(entry: entry) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("agenda-\(entry.id)")
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        // RSVP changes anywhere in the app bump the account's attendance revision.
        .task(id: RequestID(userID: account.user?.id, retry: retry, attendanceRevision: account.attendanceRevision)) {
            await store.load(account: account)
        }
    }

    private struct RequestID: Equatable {
        let userID: String?
        let retry: UUID
        let attendanceRevision: UUID
    }
}

private struct AgendaRow: View {
    let entry: AgendaEntry

    private var huddl: Huddl { entry.huddl }
    private var zone: TimeZone { TimeZone(identifier: huddl.attributes.timeZone) ?? .gmt }

    private func stamp(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: huddl.attributes.startsAt)
    }

    private var startTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.timeStyle = .short
        return "\(formatter.string(from: huddl.attributes.startsAt)) \(huddl.timeZoneLabel)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(stamp("MMM").uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(HuddlStyle.accent)
                Text(stamp("d"))
                    .font(.title3.bold())
            }
            .frame(width: 48, height: 48)
            .background(HuddlStyle.accent.opacity(0.10), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(huddl.title).font(.headline)
                Text("\(startTime) · \(huddl.location)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(entry.attendance == .waitlisted ? "Waitlisted" : "Going",
                      systemImage: entry.attendance.symbol)
                    .font(.caption.bold())
                    .foregroundStyle(HuddlStyle.accent)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(HuddlStyle.surface, in: .rect(cornerRadius: 20))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview { AgendaView().environment(AccountStore()) }
