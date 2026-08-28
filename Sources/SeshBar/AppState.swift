import AppKit
import AwseshCore
import SwiftUI

/// Login-flow state driving the device-code sheet.
struct LoginFlow: Identifiable {
    let id = UUID()
    let sessionName: String
    let info: SSOLoginInfo
}

@MainActor
final class AppState: ObservableObject {
    let service: AwseshService

    @Published var sessions: [SessionInfo] = []
    @Published var accounts: [String: [AccountInfo]] = [:]
    @Published var current: [CredentialInfo] = []
    @Published var isLoading = false
    @Published var switching: (session: String, accountId: String)? = nil
    @Published var loginFlow: LoginFlow? = nil
    @Published var loginError: String? = nil
    @Published var notice: String? = nil
    @Published var search = "" { didSet { clampSelection() } }
    @Published var selectedEntryID: String? = nil
    /// Bumped when the popover opens so the view refocuses the search field.
    @Published var focusToken = 0
    @Published var accountSettingsTarget: Entry? = nil

    /// Fires when the active credential changes, so the tray can retitle.
    var onActiveChanged: (() -> Void)?

    private var loginTask: Task<Void, Never>?

    init(service: AwseshService = AwseshService()) {
        self.service = service
    }

    var active: CredentialInfo? {
        current.first(where: \.isDefault) ?? current.first
    }

    /// The active credential outlives its SSO session (issued STS creds are
    /// not revoked by sign-out) — true when that's the current situation.
    var activeSessionSignedOut: Bool {
        guard let active else { return false }
        return !(sessions.first { $0.name == active.sessionName }?.authenticated ?? false)
    }

    // MARK: - Visible entries & keyboard selection

    struct Entry: Identifiable, Equatable {
        let session: SessionInfo
        let account: AccountInfo
        var id: String { "\(session.name)|\(account.accountId)" }
        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
    }

    private func matches(_ entry: Entry) -> Bool {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return true }
        let haystack = "\(entry.session.name) \(entry.account.name) \(entry.account.accountId) \(entry.account.roles.joined(separator: " "))".lowercased()
        return term.split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    var starredEntries: [Entry] {
        sessions.filter(\.authenticated).flatMap { session in
            (accounts[session.name] ?? []).filter(\.starred)
                .map { Entry(session: session, account: $0) }
        }.filter(matches(_:))
    }

    func sessionEntries(_ session: SessionInfo) -> [Entry] {
        (accounts[session.name] ?? []).filter { !$0.starred }
            .map { Entry(session: session, account: $0) }
            .filter(matches(_:))
    }

    /// Everything currently visible, in display order.
    var visibleEntries: [Entry] {
        starredEntries + sessions.flatMap { sessionEntries($0) }
    }

    private func clampSelection() {
        let visible = visibleEntries
        if let selected = selectedEntryID, visible.contains(where: { $0.id == selected }) { return }
        selectedEntryID = visible.first?.id
    }

    func moveSelection(_ delta: Int) {
        let visible = visibleEntries
        guard !visible.isEmpty else { return }
        guard let selected = selectedEntryID,
              let index = visible.firstIndex(where: { $0.id == selected }) else {
            selectedEntryID = (delta >= 0 ? visible.first : visible.last)?.id
            return
        }
        let next = min(max(index + delta, 0), visible.count - 1)
        selectedEntryID = visible[next].id
    }

    /// ⌘1…⌘9 switch to the Nth visible starred account.
    func quickSelect(_ number: Int) {
        let starred = starredEntries
        guard (1...starred.count).contains(number) else { return }
        let entry = starred[number - 1]
        switchTo(session: entry.session.name, account: entry.account,
                 role: defaultRole(for: entry.account))
    }

    func activateSelection() {
        guard let selected = selectedEntryID,
              let entry = visibleEntries.first(where: { $0.id == selected }) else { return }
        switchTo(session: entry.session.name, account: entry.account,
                 role: defaultRole(for: entry.account))
    }

    func popoverOpened() {
        reload()
        search = ""
        selectedEntryID = visibleEntries.first?.id
        focusToken += 1
    }

    // MARK: - Loading

    func reload() {
        do {
            sessions = try service.sessions()
            current = try service.current()
            var map: [String: [AccountInfo]] = [:]
            for session in sessions {
                map[session.name] = try service.accounts(session: session.name)
            }
            accounts = map
            onActiveChanged?()
        } catch {
            show(error)
        }
    }

    func refreshFromAWS() {
        isLoading = true
        Task {
            defer { isLoading = false }
            for session in sessions where session.authenticated {
                do {
                    accounts[session.name] = try await service.refreshAccounts(session: session.name)
                } catch let error as AwseshServiceError {
                    if case .notSignedIn(let name) = error {
                        notice = "Signed out of \(name) — sign in again."
                    } else {
                        show(error)
                    }
                } catch {
                    show(error)
                }
            }
            reload()
        }
    }

    // MARK: - Actions

    func switchTo(session: String, account: AccountInfo, role: String?) {
        switching = (session, account.accountId)
        Task {
            defer { switching = nil }
            do {
                let message = try await service.setCredentials(
                    session: session, account: account.name, role: role)
                notice = message
                reload()
            } catch let error as AwseshServiceError {
                if case .notSignedIn(let name) = error {
                    notice = "Signed out of \(name) — sign in again."
                } else {
                    show(error)
                }
                reload()
            } catch {
                show(error)
            }
        }
    }

    func toggleStar(session: String, account: AccountInfo) {
        do {
            try service.setStarred(!account.starred, session: session, accountId: account.accountId)
            reload()
        } catch {
            show(error)
        }
    }

    func clearActive() {
        do {
            _ = try service.clearActive()
            reload()
        } catch {
            show(error)
        }
    }

    func openConsole() {
        do {
            NSWorkspace.shared.open(try service.consoleURL())
        } catch {
            show(error)
        }
    }

    // MARK: - Sign in / out

    func signIn(session name: String) {
        loginError = nil
        Task {
            do {
                let info = try await service.startLogin(session: name)
                loginFlow = LoginFlow(sessionName: name, info: info)
                if let url = URL(string: info.verificationUriComplete) {
                    NSWorkspace.shared.open(url)
                }
                loginTask = Task {
                    do {
                        try await service.awaitToken(session: name, login: info)
                        self.loginFlow = nil
                        self.reload()
                        self.refreshFromAWS()
                    } catch is CancellationError {
                        // user cancelled the sheet
                    } catch {
                        self.loginError = error.localizedDescription
                    }
                }
            } catch {
                show(error)
            }
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginFlow = nil
    }

    func signOut(session name: String) {
        do {
            try service.signOut(session: name)
            reload()
        } catch {
            show(error)
        }
    }

    // MARK: - Session management

    func saveSession(_ session: SSOSession) {
        do {
            try service.saveSession(session)
            reload()
        } catch {
            show(error)
        }
    }

    func removeSession(named name: String) {
        do {
            try service.removeSession(named: name)
            reload()
        } catch {
            show(error)
        }
    }

    func saveAccountSettings(entry: Entry, defaultRole: String?, region: String?,
                             profileNamesByRole: [String: String]) {
        do {
            try service.savePreferences(session: entry.session.name,
                                        accountId: entry.account.accountId,
                                        accountName: entry.account.name,
                                        defaultRole: defaultRole, region: region,
                                        profileNamesByRole: profileNamesByRole)
            accountSettingsTarget = nil
            notice = "Saved settings for \(entry.account.name)"
            reload()
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        notice = error.localizedDescription
    }
}
