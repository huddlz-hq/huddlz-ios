import Foundation

struct Huddl: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let attributes: Attributes
    let relationships: Relationships?
    var hostName: String?

    struct Relationships: Decodable, Hashable, Sendable {
        let group: Group?
        struct Group: Decodable, Hashable, Sendable {
            let data: ResourceIdentifier?
        }
        struct ResourceIdentifier: Decodable, Hashable, Sendable {
            let type: String
            let id: String
        }
    }

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

    var timeZone: TimeZone { TimeZone(identifier: attributes.timeZone) ?? .gmt }

    var timeZoneLabel: String {
        timeZone.abbreviation(for: attributes.startsAt) ?? attributes.timeZone
    }

    /// The weekday and start time in the huddl's zone, such as "Thu 9:00 AM"; cards show the date separately.
    var startTime: String {
        attributes.startsAt.formatted(zoned.weekday(.abbreviated).hour().minute())
    }

    /// The start time alone in the huddl's zone, such as "9:00 AM", for rows already under a day heading.
    var startClock: String {
        attributes.startsAt.formatted(zoned.hour().minute())
    }

    /// The start day in the huddl's zone, such as "Thursday, September 10".
    var dayTitle: String {
        attributes.startsAt.formatted(zoned.weekday(.wide).month(.wide).day())
    }

    /// The start and end times in the huddl's zone; an end on a later day names that day.
    var timeRange: String {
        let start = startClock
        let sameDay = dayKey(attributes.startsAt) == dayKey(attributes.endsAt)
        let end = sameDay
            ? attributes.endsAt.formatted(zoned.hour().minute())
            : attributes.endsAt.formatted(zoned.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        if timeZone.secondsFromGMT(for: attributes.startsAt) != timeZone.secondsFromGMT(for: attributes.endsAt) {
            let endZone = timeZone.abbreviation(for: attributes.endsAt) ?? attributes.timeZone
            return "\(start) \(timeZoneLabel) – \(end) \(endZone)"
        }
        return "\(start) – \(end) \(timeZoneLabel)"
    }

    private var zoned: Date.FormatStyle {
        var style = Date.FormatStyle()
        style.timeZone = timeZone
        return style
    }

    private func dayKey(_ date: Date) -> String {
        date.formatted(zoned.year().month().day())
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

extension JSONDecoder {
    /// Decodes API huddl documents: snake_case keys and ISO 8601 dates with or without fractions.
    static var huddlz: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid event date"))
        }
        return decoder
    }
}
