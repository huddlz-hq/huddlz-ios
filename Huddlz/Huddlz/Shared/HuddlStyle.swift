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

/// A 48-point tile with the month over the day, as on the web app's cards. It is solid rather than glass
/// so it stays readable over busy cover art.
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
        .background(HuddlStyle.surface, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
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

/// The huddlz square emblem and wordmark shared by tab headers.
struct BrandWordmark: View {
    var body: some View {
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
        .fixedSize()
    }
}

/// The circular glass Account button, showing the signed-in member's photo when available.
struct AccountButton: View {
    let openAccount: () -> Void
    @Environment(AccountStore.self) private var account

    var body: some View {
        Button(action: openAccount) {
            if let avatarURL = account.user?.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle").font(.title3)
                }
                .frame(width: 28, height: 28)
                .clipShape(.circle)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Account")
    }
}

/// The signed-in member's profile photo, falling back to their initials circle when no photo is set.
struct AccountAvatar: View {
    let user: AccountUser
    var size: CGFloat = 64

    var body: some View {
        let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initials = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined()
        let fallback = Text(initials.isEmpty ? String(user.email.prefix(1)).uppercased() : initials.uppercased())
            .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
            .foregroundStyle(HuddlStyle.accent)
            .frame(width: size, height: size)
            .background(HuddlStyle.accent.opacity(0.12), in: .circle)

        Group {
            if let avatarURL = user.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
                .frame(width: size, height: size)
                .clipShape(.circle)
            } else {
                fallback
            }
        }
        .accessibilityHidden(true)
    }
}

/// The wordmark and glass Account button that open each tab, as on the web app's header.
struct BrandHeader: View {
    let openAccount: () -> Void

    var body: some View {
        HStack {
            BrandWordmark()
            Spacer(minLength: 8)
            AccountButton(openAccount: openAccount)
        }
    }
}

/// A square tile showing the group's image, or its initial in a stable brand tint when no image is set.
struct GroupTile: View {
    let name: String
    var imageURL: URL? = nil
    var size: CGFloat = 48

    var body: some View {
        let radius = size * 0.29
        let monogram = Text(initial)
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: radius))

        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    monogram
                }
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: radius))
            } else {
                monogram
            }
        }
        .accessibilityHidden(true)
    }

    private var tint: Color {
        let palette = [HuddlStyle.accent, HuddlStyle.online, HuddlStyle.hybrid, Color.indigo, Color.green]
        // A stable sum of the name's characters, since Swift's hash values change between launches.
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "h"
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

/// A sheet's title and subtitle with a trailing control, as on the canvas's account sheet.
struct SheetHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// A form field's label above its content.
struct FormField<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
    }
}

/// The 52-point well a text field sits in: a surface with a hairline ring.
struct FormFieldWell: ViewModifier {
    var trailingInset: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(.leading, 16)
            .padding(.trailing, trailingInset)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(HuddlStyle.surface, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary) }
    }
}

extension View {
    func formFieldWell(trailingInset: CGFloat = 16) -> some View { modifier(FormFieldWell(trailingInset: trailingInset)) }
}

extension Text {
    /// A full-width, 44-point secondary action in a sheet, such as "Forgot password?".
    func sheetLink() -> some View {
        font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
    }
}
