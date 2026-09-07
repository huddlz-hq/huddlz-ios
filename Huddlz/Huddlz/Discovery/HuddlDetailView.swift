import SwiftUI

struct HuddlDetailView: View {
    let id: Huddl.ID
    @State private var huddl: Huddl?
    @State private var errorMessage: String?
    @State private var reload = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let huddl {
                    HuddlArtwork(huddl: huddl)
                    Text(huddl.attributes.eventType.title)
                        .font(.subheadline.bold()).foregroundStyle(HuddlStyle.accent)
                    Text(huddl.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    if huddl.attributes.lifecycleState == "cancelled" {
                        Label("This huddl has been cancelled", systemImage: "calendar.badge.exclamationmark")
                            .font(.headline)
                        if let reason = huddl.attributes.cancellationReason { Text(reason) }
                    } else if huddl.attributes.lifecycleState == "completed" {
                        Text("This huddl has ended").font(.headline)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Starts: \(huddl.schedule)")
                            Text("Ends: \(huddl.endSchedule)")
                            Text(huddl.attributes.timeZone).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "calendar") }
                    if huddl.attributes.eventType != .virtual,
                       let address = huddl.attributes.physicalLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !address.isEmpty {
                        HuddlLocationView(address: address).id(address)
                    } else {
                        Label(huddl.location, systemImage: "mappin.and.ellipse")
                    }
                    Divider()
                    Text("About this huddl").font(.title2.bold())
                    Text(huddl.attributes.description?.isEmpty == false ? huddl.attributes.description! : "The organizer hasn’t added a description yet.")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if huddl.attributes.eventType != .inPerson {
                        Text("Online joining details are shared with confirmed attendees.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn’t load this huddl", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { reload = UUID() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("Loading huddl…").frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(HuddlStyle.background)
        .navigationTitle("The huddl")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: reload) { await load() }
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
