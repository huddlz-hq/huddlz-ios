import SwiftUI

struct GroupsView: View {
    var body: some View {
        NavigationStack {
            SignedInContent(title: "Sign in to see your groups", symbol: "person.2",
                            description: "The groups you belong to, and their next huddlz.") {
                ContentUnavailableView("Your groups", systemImage: "person.2",
                                       description: Text("Groups you join will appear here."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HuddlStyle.background)
            .navigationTitle("Groups")
        }
    }
}

#Preview { GroupsView().environment(AccountStore()) }
