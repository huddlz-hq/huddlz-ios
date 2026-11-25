import Foundation
import Observation

/// Reports and blocks from one huddl or group page, and what the page says afterward.
@MainActor
@Observable
final class ModerationStore {
    /// The server keeps at most this many characters of a report's details.
    static let detailsLimit = 1000
    static let sessionExpired = "Your session has expired. Please sign in again."

    let subject: ModerationSubject
    /// True once the server says this is the person's own huddl or group. Nobody reports or blocks themselves.
    private(set) var isOwn = false
    private(set) var isBlocking = false
    private(set) var isReporting = false
    private(set) var reportError: String?
    private(set) var notice: ModerationNotice?
    private var ownershipCheck = UUID()

    init(subject: ModerationSubject) { self.subject = subject }

    func checkOwnership(account: AccountStore) async {
        let check = UUID()
        ownershipCheck = check
        isOwn = false
        guard account.user != nil else { return }
        // If the check fails, the menu stays: the server still refuses a report or block of yourself.
        let own = (try? await account.isOwn(subject)) ?? false
        guard check == ownershipCheck, !Task.isCancelled else { return }
        isOwn = own
    }

    func canReport(reason: ReportReason?, details: String) -> Bool {
        reason != nil && !isReporting && !isTooLong(details)
    }

    func isTooLong(_ details: String) -> Bool {
        details.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.detailsLimit
    }

    /// Sends the report. True means staff received it, so the report sheet can close.
    func report(reason: ReportReason?, details: String, account: AccountStore) async -> Bool {
        guard let reason, canReport(reason: reason, details: details) else { return false }
        isReporting = true
        reportError = nil
        defer { isReporting = false }
        do {
            try await account.report(subject, reason: reason, details: details)
            notice = .reported
            return true
        } catch is CancellationError {
        } catch let error as ModerationError {
            reportError = error.message
        } catch AccountError.unauthorized {
            reportError = Self.sessionExpired
        } catch {
            reportError = "Couldn’t send your report. Check your connection and try again."
        }
        return false
    }

    func block(account: AccountStore) async {
        guard !isBlocking else { return }
        isBlocking = true
        defer { isBlocking = false }
        do {
            try await account.block(subject)
            notice = .blocked
        } catch is CancellationError {
        } catch let error as ModerationError {
            notice = .failed(error.message)
        } catch AccountError.unauthorized {
            notice = .failed(Self.sessionExpired)
        } catch {
            notice = .failed("Couldn’t block \(subject.person). Check your connection and try again.")
        }
    }

    func clearNotice() { notice = nil }

    /// A reopened report sheet starts without the last attempt's error.
    func clearReportError() { reportError = nil }
}
