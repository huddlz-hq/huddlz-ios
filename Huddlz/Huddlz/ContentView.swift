import SwiftUI

enum AppTab: String {
    case agenda, groups, discover
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = AccountStore()
    @SceneStorage("selectedTab") private var selectedTab = AppTab.discover

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Agenda", systemImage: "calendar", value: .agenda) { AgendaView() }
            Tab("Groups", systemImage: "person.2", value: .groups) { GroupsView() }
            // The search role places Discover in its own circle beside the other tabs.
            Tab("Discover", systemImage: "magnifyingglass", value: .discover, role: .search) { DiscoveryView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(HuddlStyle.accent)
        .environment(account)
        .task { await account.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.restore() } }
        }
    }
}

#Preview("Light") { ContentView().preferredColorScheme(.light) }
#Preview("Dark") { ContentView().preferredColorScheme(.dark) }
