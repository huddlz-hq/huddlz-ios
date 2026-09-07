import Foundation

struct Huddl: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable, Hashable, Sendable {
        let title: String
        let description: String?
        let startsAt: Date
        let endsAt: Date
        let timeZone: String
        let eventType: EventType
        let physicalLocation: String?
        let thumbnailUrl: String?
        let imageUrl: String?
        let lifecycleState: String
        let cancellationReason: String?
    }

    var title: String { attributes.title }

    var imageURL: URL? {
        guard let text = (attributes.imageUrl ?? attributes.thumbnailUrl)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var location: String {
        if let location = attributes.physicalLocation, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return location
        }
        return attributes.eventType == .virtual ? "Online" : "Location to be announced"
    }

    var schedule: String { formattedDate(attributes.startsAt) }
    var endSchedule: String { formattedDate(attributes.endsAt) }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: attributes.timeZone) ?? .gmt
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var timeZoneLabel: String {
        let zone = TimeZone(identifier: attributes.timeZone) ?? .gmt
        return zone.abbreviation(for: attributes.startsAt) ?? attributes.timeZone
    }
}

enum EventType: String, Decodable, CaseIterable, Identifiable, Sendable {
    case inPerson = "in_person"
    case virtual
    case hybrid

    var id: Self { self }
    var title: String {
        switch self {
        case .inPerson: "In person"
        case .virtual: "Online"
        case .hybrid: "Hybrid"
        }
    }
    var symbol: String {
        switch self {
        case .inPerson: "person.2.fill"
        case .virtual: "video.fill"
        case .hybrid: "globe"
        }
    }
}

enum DiscoveryDates: String, CaseIterable, Identifiable, Sendable {
    case upcoming
    case thisWeek = "this_week"
    case thisMonth = "this_month"

    var id: Self { self }
    var title: String {
        switch self {
        case .upcoming: "All upcoming"
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        }
    }
}

struct DiscoveryQuery: Equatable, Sendable {
    var text = ""
    var dates = DiscoveryDates.upcoming
    var eventType: EventType?
    var timeZone = TimeZone.current.identifier
    var place: DiscoveryPlace?
    var distanceMiles = 25
}

struct DiscoveryPlace: Equatable, Hashable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZone: String?
}
