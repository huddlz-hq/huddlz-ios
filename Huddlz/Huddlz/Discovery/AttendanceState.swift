import Foundation

enum AttendanceState: String, Decodable {
    case confirmed, waitlisted, none

    var title: String {
        switch self {
        case .confirmed: "You’re going"
        case .waitlisted: "You’re on the waitlist"
        case .none: "You haven’t RSVP’d"
        }
    }

    var symbol: String {
        switch self {
        case .confirmed: "checkmark.circle.fill"
        case .waitlisted: "clock"
        case .none: "calendar"
        }
    }
}

/// RSVPs open only while a huddl is published and hasn't ended.
enum RSVPWindow {
    static func isOpen(lifecycleState: String, endsAt: Date, now: Date = .now) -> Bool {
        lifecycleState == "published" && endsAt > now
    }
}
