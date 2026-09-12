import SwiftUI

struct AgendaView: View {
    var body: some View {
        NavigationStack {
            SignedInContent(title: "Sign in to see your agenda", symbol: "calendar",
                            description: "Your RSVPs and waitlists, by date.") {
                ContentUnavailableView("Your agenda", systemImage: "calendar",
                                       description: Text("Huddlz you RSVP to will appear here."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HuddlStyle.background)
            .navigationTitle("Agenda")
        }
    }
}

#Preview { AgendaView().environment(AccountStore()) }
