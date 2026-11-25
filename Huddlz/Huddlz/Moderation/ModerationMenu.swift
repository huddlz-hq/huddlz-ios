import SwiftUI

extension View {
    /// Adds the More menu to a huddl or group page: report it, or block whoever runs it.
    /// Show it once the page has loaded, so nobody reports a page they can't see.
    func moderation(of subject: ModerationSubject, isShown: Bool) -> some View {
        modifier(ModerationMenu(subject: subject, isShown: isShown))
    }
}

private struct ModerationMenu: ViewModifier {
    let isShown: Bool
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var store: ModerationStore
    @State private var showsAccount = false
    @State private var showsReport = false
    @State private var confirmsBlock = false

    init(subject: ModerationSubject, isShown: Bool) {
        self.isShown = isShown
        _store = State(initialValue: ModerationStore(subject: subject))
    }

    private var subject: ModerationSubject { store.subject }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isShown, !store.isOwn {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
            .task(id: account.user?.id) { await store.checkOwnership(account: account) }
            .sheet(isPresented: $showsAccount) { AccountView() }
            .sheet(isPresented: $showsReport) { ReportView(store: store) }
            .alert(store.notice.map(subject.title(of:)) ?? "",
                   isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.clearNotice() } }),
                   presenting: store.notice) { notice in
                // Their huddlz are gone from the lists, so a block returns the person to where they came from.
                Button("OK") { if notice == .blocked { dismiss() } }
            } message: { notice in
                Text(subject.message(of: notice))
            }
    }

    private var menu: some View {
        Menu {
            if account.user == nil {
                Button("Sign in to report or block", systemImage: "person.crop.circle") { showsAccount = true }
            } else {
                Button(subject.reportTitle, systemImage: "flag") {
                    store.clearReportError()
                    showsReport = true
                }
                Button(subject.blockTitle, systemImage: "hand.raised", role: .destructive) { confirmsBlock = true }
                    .disabled(store.isBlocking)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .accessibilityLabel("More options")
        // On the menu itself, so the confirmation opens from the button the person tapped.
        .confirmationDialog(subject.blockQuestion, isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button(subject.blockTitle, role: .destructive) { Task { await store.block(account: account) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(subject.blockExplanation)
        }
    }
}

/// Mirrors the web's report dialog: a required reason, optional details, and one thanks.
private struct ReportView: View {
    let store: ModerationStore
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details = ""

    private var subject: ModerationSubject { store.subject }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: subject.reportQuestion, subtitle: subject.reportExplanation) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close report")
                    .disabled(store.isReporting)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("What’s wrong")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(ReportReason.allCases) { option in
                        reasonButton(option)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    FormField("Details") {
                        TextField("What you saw, in a sentence or two.", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(.vertical, 14)
                            .formFieldWell()
                            .disabled(store.isReporting)
                    }
                    Text(store.isTooLong(details)
                         ? "Keep the details to \(ModerationStore.detailsLimit.formatted()) characters or fewer."
                         : "Optional. Shared with huddlz staff along with your name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                Button(action: send) {
                    Label(subject.reportTitle, systemImage: "flag")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .disabled(!store.canReport(reason: reason, details: details))
                if store.isReporting { ProgressView("Sending…") }
                if let message = store.reportError { Text(message).foregroundStyle(.secondary) }
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .presentationBackground(.regularMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.isReporting)
    }

    private func reasonButton(_ option: ReportReason) -> some View {
        let selected = reason == option
        return Button { reason = option } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? HuddlStyle.accent : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.headline)
                    Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .surfaceCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("report-reason-\(option.rawValue)")
        .disabled(store.isReporting)
    }

    private func send() {
        Task {
            if await store.report(reason: reason, details: details, account: account) { dismiss() }
        }
    }
}
