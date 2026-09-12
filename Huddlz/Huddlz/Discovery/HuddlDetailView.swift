import SwiftUI

struct HuddlDetailView: View {
    let id: Huddl.ID
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var huddl: Huddl?
    @State private var errorMessage: String?
    @State private var reload = UUID()

    var body: some View {
        ScrollView {
            if let huddl {
                VStack(alignment: .leading, spacing: 0) {
                    cover(huddl)
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            EventTypePill(eventType: huddl.attributes.eventType)
                            Text(huddl.title)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }
                        HuddlAttendanceView(id: id, lifecycleState: huddl.attributes.lifecycleState, endsAt: huddl.attributes.endsAt)
                        if huddl.attributes.lifecycleState == "cancelled" {
                            notice("This huddl has been cancelled", symbol: "calendar.badge.exclamationmark",
                                   detail: huddl.attributes.cancellationReason)
                        } else if huddl.attributes.lifecycleState == "completed" {
                            notice("This huddl has ended", symbol: "calendar.badge.checkmark", detail: nil)
                        }
                        whenAndWho(huddl)
                        location(huddl)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About this huddl").font(.title3.bold())
                            Text(huddl.attributes.description?.isEmpty == false ? huddl.attributes.description! : "The organizer hasn’t added a description yet.")
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if huddl.attributes.eventType != .inPerson {
                            HuddlJoiningView(id: id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    // The content starts over the cover's fade, as on the canvas.
                    .padding(.top, -28)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t load this huddl", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { reload = UUID() }.buttonStyle(.glassProminent)
                }
                .padding(20)
            } else {
                ProgressView("Loading huddl…").frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .background { AmbientBackground() }
        .navigationTitle("The huddl")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: reload) { await load() }
    }

    /// The cover fades into whatever is behind it; on wide layouts it becomes a rounded band.
    private func cover(_ huddl: Huddl) -> some View {
        HuddlArtwork(huddl: huddl, fullBleed: true, symbolSize: 84)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                }
            }
            .clipShape(.rect(cornerRadius: horizontalSizeClass == .regular ? 24 : 0))
            .padding(.top, horizontalSizeClass == .regular ? 20 : 0)
    }

    private func notice(_ title: String, symbol: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(HuddlStyle.hybrid)
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    /// The hosting group, when known, above the day and time range in the event's zone.
    private func whenAndWho(_ huddl: Huddl) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hostName = huddl.hostName, let host = huddl.relationships?.group?.data, host.type == "group" {
                NavigationLink {
                    GroupDetailView(id: host.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(HuddlStyle.accent)
                            .frame(width: 40, height: 40)
                            .background(HuddlStyle.accent.opacity(0.12), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hosted by").font(.footnote).foregroundStyle(.secondary)
                            Text(hostName).font(.headline)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View group: \(hostName)")
                Divider().padding(.horizontal, 16)
            }
            HStack(spacing: 12) {
                DateStamp(date: huddl.attributes.startsAt, timeZone: huddl.timeZone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(huddl.dayTitle).font(.headline)
                    Text(huddl.timeRange).font(.subheadline).foregroundStyle(.secondary)
                    Text(huddl.attributes.timeZone).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .surfaceCard()
    }

    @ViewBuilder private func location(_ huddl: Huddl) -> some View {
        if huddl.attributes.eventType != .virtual,
           let address = huddl.attributes.physicalLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty {
            HuddlLocationView(address: address).id(address)
        } else {
            Label(huddl.location, systemImage: huddl.attributes.eventType == .virtual ? "video" : "mappin.and.ellipse")
                .font(.headline)
                .foregroundStyle(huddl.attributes.eventType.tint)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            let result = try await DiscoveryClient().detail(id: id)
            guard !Task.isCancelled else { return }
            huddl = result
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
