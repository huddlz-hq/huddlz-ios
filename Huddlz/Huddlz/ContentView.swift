import SwiftUI

struct ContentView: View {
    var body: some View {
        DiscoveryView()
            .tint(HuddlStyle.accent)
    }
}

#Preview("Light") { ContentView().preferredColorScheme(.light) }
#Preview("Dark") { ContentView().preferredColorScheme(.dark) }
