import SwiftUI

enum HuddlStyle {
    static let accent = Color("AccentColor")
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct HuddlArtwork: View {
    let huddl: Huddl

    var body: some View {
        AsyncImage(url: huddl.attributes.thumbnailUrl) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                HuddlStyle.accent.opacity(0.10)
                Image(systemName: huddl.attributes.eventType.symbol)
                    .font(.system(size: 58, weight: .medium))
                    .foregroundStyle(HuddlStyle.accent)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityHidden(true)
    }
}

struct HuddlCard: View {
    let huddl: Huddl

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HuddlArtwork(huddl: huddl)
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
