import SwiftUI

extension View {
    /// Adds the huddl page's More menu: report or block whoever organized this huddl.
    func organizerModeration(huddlID: Huddl.ID) -> some View {
        modifier(OrganizerModeration(huddlID: huddlID))
    }
}

/// The app never shows who organized a huddl, so people report and block "the organizer" of the huddl in front of them.
private struct OrganizerModeration: ViewModifier {
    let huddlID: Huddl.ID
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var organizedByMe = false
    @State private var showsAccount = false
    @State private var showsReport = false
    @State private var confirmsBlock = false
    @State private var isBlocking = false
    @State private var notice: Notice?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !organizedByMe {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
            .task(id: account.user?.id) {
                organizedByMe = false
                guard account.user != nil else { return }
                // If this check fails, the menu stays; the API still refuses to report or block yourself.
                organizedByMe = (try? await account.organizedByMe(huddlID: huddlID)) ?? false
            }
            .sheet(isPresented: $showsAccount) { AccountView() }
            .sheet(isPresented: $showsReport) {
                ReportOrganizerView(huddlID: huddlID) { notice = .reported }
            }
            .confirmationDialog("Block this organizer?", isPresented: $confirmsBlock, titleVisibility: .visible) {
                Button("Block organizer", role: .destructive) { block() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won’t see huddlz they organize when you search or browse groups. They won’t be told. You can unblock them from your account.")
            }
            .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
                   presenting: notice) { notice in
                Button("OK") { if case .blocked = notice { dismiss() } }
            } message: { notice in
                Text(notice.message)
            }
    }

    private var menu: some View {
        Menu {
            if account.user == nil {
                Button("Sign in to report or block", systemImage: "person.crop.circle") { showsAccount = true }
            } else {
                Button("Report organizer", systemImage: "flag") { showsReport = true }
                Button("Block organizer", systemImage: "hand.raised", role: .destructive) { confirmsBlock = true }
                    .disabled(isBlocking)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .accessibilityLabel("More options")
    }

    private func block() {
        guard !isBlocking else { return }
        isBlocking = true
        Task {
            defer { isBlocking = false }
            do {
                try await account.blockOrganizer(huddlID: huddlID)
                notice = .blocked
            } catch is CancellationError {
                return
            } catch let error as ModerationError {
                notice = .failed(error.message)
            } catch {
                notice = .failed("Couldn’t block this organizer. Check your connection and try again.")
            }
        }
    }

    private enum Notice {
        case reported, blocked
        case failed(String)

        var title: String {
            switch self {
            case .reported: "Thanks—we’ve received your report."
            case .blocked: "Organizer blocked"
            case .failed: "Something went wrong"
            }
        }

        var message: String {
            switch self {
            case .reported: "Only huddlz staff can see your report and who sent it. We won’t tell the organizer."
            case .blocked: "Huddlz they organize won’t show up when you search or browse groups."
            case .failed(let message): message
            }
        }
    }
}

/// Mirrors the web's report dialog: a required reason, optional details, and one thanks.
struct ReportOrganizerView: View {
    let huddlID: Huddl.ID
    var onReported: () -> Void
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "Report the organizer?",
                            subtitle: "Only huddlz staff can review your report and see who sent it. We won’t notify the organizer or send you updates about the outcome.") {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close report")
                    .disabled(isSending)
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
                FormField("Details") {
                    TextField("What you saw, in a sentence or two.", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(.vertical, 14)
                        .formFieldWell()
                }
                Text("Optional. Shared with huddlz staff along with your name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: send) {
                    Label("Report organizer", systemImage: "flag")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .disabled(reason == nil || isSending || details.count > 1000)
                if isSending { ProgressView("Sending…") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationBackground(.regularMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSending)
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
        .disabled(isSending)
    }

    private func send() {
        guard let reason, !isSending else { return }
        isSending = true
        errorMessage = nil
        Task {
            defer { isSending = false }
            do {
                try await account.reportOrganizer(huddlID: huddlID, reason: reason, details: details)
                dismiss()
                onReported()
            } catch is CancellationError {
                return
            } catch let error as ModerationError {
                errorMessage = error.message
            } catch {
                errorMessage = "Couldn’t send your report. Check your connection and try again."
            }
        }
    }
}
