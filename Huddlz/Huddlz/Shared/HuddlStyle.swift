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
    var isDiscoveryCover = false

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: huddl.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        if isDiscoveryCover {
                            LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            HuddlStyle.accent.opacity(0.10)
                        }
                        Image(systemName: huddl.attributes.eventType.symbol)
                            .font(.system(size: 58, weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: isDiscoveryCover ? 0 : 24))
            .accessibilityHidden(true)
    }

    private var tint: Color { isDiscoveryCover ? huddl.attributes.eventType.tint : HuddlStyle.accent }
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
