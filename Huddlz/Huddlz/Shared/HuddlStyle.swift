import SwiftUI

enum HuddlStyle {
    /// The huddlz web palette: teal accent, pink for online huddlz, a warm tone for hybrid ones.
    static let accent = Color("AccentColor")
    static let online = Color("OnlineColor")
    static let hybrid = Color("HybridColor")
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardRadius: CGFloat = 20
}

extension EventType {
    var tint: Color {
        switch self {
        case .inPerson: HuddlStyle.accent
        case .virtual: HuddlStyle.online
        case .hybrid: HuddlStyle.hybrid
        }
    }
}

/// The grouped background with the web app's soft accent and pink glows behind the content.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            HuddlStyle.background
            Circle()
                .fill(HuddlStyle.accent.opacity(0.14))
                .frame(width: 340, height: 340)
                .blur(radius: 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -90, y: -40)
            Circle()
                .fill(HuddlStyle.online.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 130)
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct HuddlArtwork: View {
    let huddl: Huddl
    var cornerRadius: CGFloat = 24

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: huddl.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: huddl.attributes.eventType.symbol)
                            .font(.system(size: 58, weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }

    private var tint: Color { huddl.attributes.eventType.tint }
}

/// A 48-point glass tile with the month over the day, as on the web app's cards.
struct DateStamp: View {
    let date: Date
    let timeZone: TimeZone

    var body: some View {
        VStack(spacing: 1) {
            Text(date.formatted(style.month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(HuddlStyle.accent)
            Text(date.formatted(style.day()))
                .font(.system(size: 18, weight: .bold))
        }
        .frame(width: 48, height: 48)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(style.month(.abbreviated).day()))
    }

    private var style: Date.FormatStyle {
        var style = Date.FormatStyle()
        style.timeZone = timeZone
        return style
    }
}

struct HuddlCard: View {
    let huddl: Huddl
    var attendance: AttendanceState? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HuddlArtwork(huddl: huddl, cornerRadius: 0)
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
        .background(HuddlStyle.surface)
        .clipShape(.rect(cornerRadius: HuddlStyle.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: HuddlStyle.cardRadius).strokeBorder(.quaternary) }
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
