import SwiftUI

struct AgendaView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountStore.self) private var account
    @State private var store = AgendaStore()
    @State private var retry = UUID()
    @State private var isShowingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    BrandHeader { isShowingAccount = true }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your agenda")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                    SignedInContent(title: "Sign in to see your agenda", symbol: "calendar",
                                    description: "Your RSVPs and waitlists, by date.") {
                        // One view, so the day cards share the stack's spacing and the sign-in sheet attaches once.
                        VStack(alignment: .leading, spacing: 20) { list }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background { AmbientBackground() }
            .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
            .navigationTitle("Agenda")
            // RSVP changes anywhere in the app bump the account's attendance revision.
            .task(id: RequestID(userID: account.user?.id, retry: retry, attendanceRevision: account.attendanceRevision)) {
                await store.load(account: account)
            }
        }
        .sheet(isPresented: $isShowingAccount) { AccountView() }
    }

    /// Counts the loaded huddlz; otherwise says what the tab holds.
    private var subtitle: String {
        let count = store.days.reduce(0) { $0 + $1.entries.count }
        guard account.user != nil, store.loadedUserID != nil, count > 0 else {
            return "Your RSVPs and waitlists, by date."
        }
        if count == 1 { return "One huddl coming up." }
        let number = count < 10 ? Self.spelledOut.string(from: count as NSNumber) ?? "\(count)" : count.formatted()
        return "\(number.prefix(1).uppercased())\(number.dropFirst()) huddlz coming up."
    }

    private static let spelledOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter
    }()

    @ViewBuilder private var list: some View {
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
                    .buttonStyle(.glassProminent)
            }
        } else if store.loadedUserID != nil, store.days.isEmpty {
            ContentUnavailableView("Nothing on your agenda", systemImage: "calendar",
                                   description: Text("RSVP to a huddl in Discover and it will show up here."))
        } else {
            ForEach(store.days) { day in
                daySection(day)
            }
        }
    }

    /// A day's huddlz share one card under a small heading, as on the canvas.
    private func daySection(_ day: AgendaDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.horizontal, 16) }
                    NavigationLink { HuddlDetailView(id: entry.id) } label: { AgendaRow(entry: entry) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("agenda-\(entry.id)")
                }
            }
            .surfaceCard()
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
    private var time: String { "\(huddl.startClock) \(huddl.timeZoneLabel)" }

    var body: some View {
        HStack(spacing: 12) {
            DateStamp(date: huddl.attributes.startsAt, timeZone: huddl.timeZone)
            VStack(alignment: .leading, spacing: 3) {
                Text(huddl.title).font(.headline)
                // The meta line stacks at larger text sizes instead of squeezing the location.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(time)
                        Circle().fill(.tertiary).frame(width: 3, height: 3)
                        Text(huddl.location).lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(time)
                        Text(huddl.location).lineLimit(2)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TintPill(title: entry.attendance == .waitlisted ? "Waitlisted" : "Going",
                     tint: entry.attendance == .waitlisted ? HuddlStyle.hybrid : HuddlStyle.accent)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview { AgendaView().environment(AccountStore()) }
