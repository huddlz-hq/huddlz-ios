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
    /// Full-bleed covers (Discover cards, the huddl page) drop the corner radius and tint the fallback by event type.
    var fullBleed = false
    var symbolSize: CGFloat = 58

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: huddl.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        if fullBleed {
                            LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            HuddlStyle.accent.opacity(0.10)
                        }
                        Image(systemName: huddl.attributes.eventType.symbol)
                            .font(.system(size: symbolSize, weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: fullBleed ? 0 : 24))
            .accessibilityHidden(true)
    }

    private var tint: Color { fullBleed ? huddl.attributes.eventType.tint : HuddlStyle.accent }
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

/// A small capsule with a dot and a label in one tint: event types on cards, RSVP states on the agenda.
struct TintPill: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 6, height: 6)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// A small pill naming the event type in its color.
struct EventTypePill: View {
    let eventType: EventType

    var body: some View {
        TintPill(title: eventType.title, tint: eventType.tint)
    }
}

/// The wordmark and glass Account button that open each tab, as on the web app's header.
struct BrandHeader: View {
    let openAccount: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Text("h")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(width: 28, height: 28)
                    .background(HuddlStyle.accent, in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)
                Text("huddlz")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.5)
            }
            Spacer(minLength: 8)
            Button(action: openAccount) {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Account")
        }
    }
}

/// The rounded surface card used for grouped rows on detail pages.
struct SurfaceCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(HuddlStyle.surface)
            .clipShape(.rect(cornerRadius: HuddlStyle.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: HuddlStyle.cardRadius).strokeBorder(.quaternary) }
    }
}

extension View {
    func surfaceCard() -> some View { modifier(SurfaceCard()) }
}

struct HuddlCard: View {
    let huddl: Huddl
    var attendance: AttendanceState? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                HuddlArtwork(huddl: huddl)
                if attendance == .confirmed || attendance == .waitlisted {
                    Label(attendance == .confirmed ? "Going" : "Waitlisted",
                          systemImage: attendance == .confirmed ? "checkmark.circle.fill" : "clock")
                        .font(.caption.bold())
                        .foregroundStyle(HuddlStyle.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                }
            }
            Text(huddl.attributes.eventType.title)
                .font(.caption.bold())
                .foregroundStyle(HuddlStyle.accent)
            Text(huddl.title)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Label("\(huddl.schedule) \(huddl.timeZoneLabel)", systemImage: "calendar")
            Label(huddl.location, systemImage: "mappin.and.ellipse")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HuddlStyle.surface, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}
