import Foundation

/// The page a person reports or blocks from. The app never shows who organizes a huddl or owns a group,
/// so people name the page in front of them and the server finds the account behind it.
enum ModerationSubject: Hashable, Sendable {
    /// The organizer of this huddl.
    case huddl(Huddl.ID)
    /// The owner of this group.
    case group(HostingGroup.ID)

    var id: String {
        switch self {
        case .huddl(let id), .group(let id): id
        }
    }

    /// The report and block endpoints end in this: `blocks/organizer` or `blocks/group`.
    var route: String {
        switch self {
        case .huddl: "organizer"
        case .group: "group"
        }
    }

    var idKey: String {
        switch self {
        case .huddl: "huddl_id"
        case .group: "group_id"
        }
    }
}

/// The words people read, which differ only in who the page belongs to.
extension ModerationSubject {
    var person: String {
        switch self {
        case .huddl: "the organizer"
        case .group: "the group’s owner"
        }
    }

    var reportTitle: String {
        switch self {
        case .huddl: "Report organizer"
        case .group: "Report group"
        }
    }

    var reportQuestion: String {
        switch self {
        case .huddl: "Report the organizer?"
        case .group: "Report this group?"
        }
    }

    var reportExplanation: String {
        "Only huddlz staff can review your report and see who sent it. We won’t notify \(person) or send you updates about the outcome."
    }

    var blockTitle: String {
        switch self {
        case .huddl: "Block organizer"
        case .group: "Block group owner"
        }
    }

    var blockQuestion: String {
        switch self {
        case .huddl: "Block this organizer?"
        case .group: "Block this group’s owner?"
        }
    }

    var blockExplanation: String {
        "You won’t see huddlz they organize when you search or browse groups. They won’t be told. You can unblock them from your account."
    }

    var blockRefused: String {
        switch self {
        case .huddl: "This organizer can’t be blocked."
        case .group: "This group’s owner can’t be blocked."
        }
    }

    func title(of notice: ModerationNotice) -> String {
        switch (notice, self) {
        case (.reported, _): "Thanks—we’ve received your report."
        case (.blocked, .huddl): "Organizer blocked"
        case (.blocked, .group): "Group owner blocked"
        case (.failed, _): "Something went wrong"
        }
    }

    func message(of notice: ModerationNotice) -> String {
        switch notice {
        case .reported: "Only huddlz staff can see your report and who sent it. We won’t tell \(person)."
        case .blocked: "Huddlz they organize won’t show up when you search or browse groups."
        case .failed(let message): message
        }
    }
}

/// What the page tells the person once a report or block finishes.
enum ModerationNotice: Equatable {
    case reported, blocked
    case failed(String)
}

enum ReportReason: String, CaseIterable, Identifiable {
    case spam, other

    var id: Self { self }
    var title: String {
        switch self {
        case .spam: "Spam or advertising"
        case .other: "Other"
        }
    }
    var detail: String {
        switch self {
        case .spam: "Promotions, coin listings, affiliate links, fake huddlz."
        case .other: "Anything else huddlz staff should look at."
        }
    }
}

struct BlockedPerson: Identifiable, Equatable {
    let id: String
    let name: String
}

struct ModerationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
