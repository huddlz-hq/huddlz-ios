import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = AccountStore()

    var body: some View {
        DiscoveryView()
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
