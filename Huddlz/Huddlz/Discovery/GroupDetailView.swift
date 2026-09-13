import SwiftUI

struct HostingGroup: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let description: String?
        let location: String?
    }
}

struct GroupDetailView: View {
    let id: String
    @State private var group: HostingGroup?
    @State private var huddlz: [Huddl] = []
    @State private var hasLoadedHuddlz = false
    @State private var huddlzError: String?
    @State private var errorMessage: String?
    @State private var reload = UUID()
    @State private var nextPage: URL?
    @State private var isLoadingMore = false
    @State private var moreError = false
    @State private var moreRequest: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let group {
                    HStack(spacing: 14) {
                        GroupTile(name: group.attributes.name, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.attributes.name)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            if let location = group.attributes.location, !location.isEmpty {
                                Label(location, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this group").font(.title3.bold())
                        Text(group.attributes.description ?? "The group hasn’t added a description yet.")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Upcoming huddlz").font(.title3.bold())
                    if let huddlzError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn’t load upcoming huddlz.").font(.headline)
                            Text(huddlzError).foregroundStyle(.secondary)
                            Button("Try loading huddlz again") { reload = UUID() }.buttonStyle(.glass)
                        }
                    } else if !hasLoadedHuddlz {
                        ProgressView("Loading huddlz…").frame(maxWidth: .infinity, minHeight: 120)
                    } else if huddlz.isEmpty {
                        ContentUnavailableView("No upcoming huddlz", systemImage: "calendar",
                                               description: Text("Check back for the group’s next gathering."))
                    }
                    ForEach(huddlz) { huddl in
                        NavigationLink { HuddlDetailView(id: huddl.id) } label: { HuddlCard(huddl: huddl) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("huddl-\(huddl.id)")
                    }
                    if nextPage != nil {
                        if isLoadingMore {
                            ProgressView("Loading more…").frame(maxWidth: .infinity)
                        } else {
                            if moreError { Text("Couldn’t load more huddlz.").foregroundStyle(.secondary) }
                            Button(moreError ? "Try loading more again" : "Load more huddlz") { moreRequest = UUID() }
                                .buttonStyle(.glass)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn’t load this group", systemImage: "person.2.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { reload = UUID() }.buttonStyle(.glassProminent)
                    }
                } else {
                    ProgressView("Loading group…").frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background { AmbientBackground() }
        .navigationTitle("The group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: reload) { await load() }
        .task(id: moreRequest) {
            if moreRequest != nil { await loadMore() }
        }
    }

    private func load() async {
        let client = DiscoveryClient()
        if group == nil {
            errorMessage = nil
            do {
                let result = try await client.group(id: id)
                try Task.checkCancellation()
                group = result
            } catch {
                guard !Task.isCancelled else { return }
                if case DiscoveryError.notFound = error {
                    errorMessage = "This group is no longer available."
                } else {
                    errorMessage = "The group couldn’t load right now. Please try again."
                }
                return
            }
        }
        guard !hasLoadedHuddlz else { return }
        huddlzError = nil
        do {
            let page = try await client.groupHuddlz(id: id)
            try Task.checkCancellation()
            huddlz = page.huddlz
            nextPage = page.next
            hasLoadedHuddlz = true
        } catch {
            guard !Task.isCancelled else { return }
            huddlzError = "Please try again."
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, let url = nextPage else { return }
        isLoadingMore = true
        moreError = false
        defer { isLoadingMore = false }
        do {
            let page = try await DiscoveryClient().groupPage(at: url, id: id)
            try Task.checkCancellation()
            var ids = Set(huddlz.map(\.id))
            huddlz.append(contentsOf: page.huddlz.filter { ids.insert($0.id).inserted })
            nextPage = page.next == url ? nil : page.next
        } catch {
            guard !Task.isCancelled else { return }
            moreError = true
        }
    }

}
