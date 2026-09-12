import Foundation
import Observation

/// One upcoming huddl on the member's agenda with their RSVP.
struct AgendaEntry: Identifiable, Hashable, Sendable, Decodable {
    let huddl: Huddl
    let attendance: AttendanceState
    var id: String { huddl.id }

    init(huddl: Huddl, attendance: AttendanceState) {
        self.huddl = huddl
        self.attendance = attendance
    }

    // The RSVP rides alongside the huddl's own attributes in the same resource.
    init(from decoder: Decoder) throws {
        struct Attributes: Decodable { let attendanceState: AttendanceState? }
        struct Resource: Decodable { let attributes: Attributes }
        huddl = try Huddl(from: decoder)
        attendance = try Resource(from: decoder).attributes.attendanceState ?? .none
    }
}

struct AgendaDay: Identifiable, Equatable {
    let id: String
    let title: String
    let entries: [AgendaEntry]

    /// Groups entries soonest first by calendar day in each huddl's own time zone.
    static func days(for entries: [AgendaEntry]) -> [AgendaDay] {
        let sorted = entries.sorted { $0.huddl.attributes.startsAt < $1.huddl.attributes.startsAt }
        var days: [AgendaDay] = []
        for entry in sorted {
            let zone = TimeZone(identifier: entry.huddl.attributes.timeZone) ?? .gmt
            let key = DateFormatter()
            key.timeZone = zone
            key.dateFormat = "yyyy-MM-dd"
            let id = key.string(from: entry.huddl.attributes.startsAt)
            if let index = days.firstIndex(where: { $0.id == id }) {
                days[index] = AgendaDay(id: id, title: days[index].title, entries: days[index].entries + [entry])
            } else {
                let title = DateFormatter()
                title.timeZone = zone
                title.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
                days.append(AgendaDay(id: id, title: title.string(from: entry.huddl.attributes.startsAt), entries: [entry]))
            }
        }
        return days
    }
}

/// Holds the signed-in member's upcoming RSVPs; responses for a previous account never apply.
@MainActor
@Observable
final class AgendaStore {
    private(set) var days: [AgendaDay] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    private(set) var loadedUserID: String?
    private var revision = UUID()

    func clear() {
        revision = UUID()
        days = []
        loadedUserID = nil
        isLoading = false
        loadFailed = false
    }

    func load(account: AccountStore) async {
        clear()
        guard let userID = account.user?.id else { return }
        let request = revision
        isLoading = true
        defer { if request == revision { isLoading = false } }
        do {
            let entries = try await account.agenda()
            guard request == revision, !Task.isCancelled else { return }
            days = AgendaDay.days(for: entries)
            loadedUserID = userID
        } catch is CancellationError {
            return
        } catch {
            guard request == revision, !Task.isCancelled else { return }
            loadFailed = true
            loadedUserID = userID
        }
    }
}
