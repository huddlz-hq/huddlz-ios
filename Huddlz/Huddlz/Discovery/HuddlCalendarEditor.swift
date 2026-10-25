import EventKit
import EventKitUI
import SwiftUI

/// Apple's new-event sheet, filled in with the huddl. The person saves it to a calendar they choose,
/// so the app never needs calendar access.
struct HuddlCalendarEditor: UIViewControllerRepresentable {
    let huddl: Huddl
    @Environment(\.dismiss) private var dismiss

    private static let store = EKEventStore()

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let event = EKEvent(eventStore: Self.store)
        event.title = huddl.title
        event.startDate = huddl.attributes.startsAt
        event.endDate = huddl.attributes.endsAt
        event.timeZone = huddl.timeZone
        event.location = huddl.attributes.eventType == .virtual ? nil : huddl.attributes.physicalLocation
        event.url = huddl.webURL
        event.notes = huddl.attributes.description
        let controller = EKEventEditViewController()
        controller.eventStore = Self.store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let finish: () -> Void
        init(finish: @escaping () -> Void) { self.finish = finish }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            finish()
        }
    }
}
