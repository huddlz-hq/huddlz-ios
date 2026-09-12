import SwiftUI

struct DiscoveryHuddlCard: View {
    let huddl: Huddl
    var attendance: AttendanceState? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HuddlArtwork(huddl: huddl, fullBleed: true)
                .overlay(alignment: .top) {
                    HStack(alignment: .top) {
                        DateStamp(date: huddl.attributes.startsAt, timeZone: huddl.timeZone)
                        Spacer(minLength: 8)
                        tag
                    }
                    .padding(12)
                }
            VStack(alignment: .leading, spacing: 6) {
                if let hostName = huddl.hostName {
                    Text(hostName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(huddl.title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                // The meta line stacks at larger text sizes instead of pushing the location off the card.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(time)
                        ForEach(details, id: \.self) { detail in
                            Circle().fill(.tertiary).frame(width: 3, height: 3)
                            Text(detail).lineLimit(1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(time)
                        ForEach(details, id: \.self) { Text($0).lineLimit(2) }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }

    private var time: String { "\(huddl.startTime) \(huddl.timeZoneLabel)" }

    private var badge: AttendanceState? {
        attendance == .confirmed || attendance == .waitlisted ? attendance : nil
    }

    /// The event type moves into this line when an RSVP takes the tag's place, and a
    /// location that only repeats the type (an online huddl with no venue) is not said twice.
    private var details: [String] {
        let type = huddl.attributes.eventType.title
        if badge != nil { return type == huddl.location ? [huddl.location] : [type, huddl.location] }
        return type == huddl.location ? [] : [huddl.location]
    }

    @ViewBuilder private var tag: some View {
        Group {
            if let badge {
                Label(badge == .confirmed ? "Going" : "Waitlisted", systemImage: badge.symbol)
                    .foregroundStyle(HuddlStyle.accent)
            } else {
                HStack(spacing: 6) {
                    Circle().frame(width: 6, height: 6)
                    Text(huddl.attributes.eventType.title)
                }
                .foregroundStyle(huddl.attributes.eventType.tint)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .glassEffect()
    }
}
