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

    /// Fires when the active credential changes, so the tray can retitle.
    var onActiveChanged: (() -> Void)?

    private var loginTask: Task<Void, Never>?

    init(service: AwseshService = AwseshService()) {
        self.service = service
    }

    var active: CredentialInfo? {
        current.first(where: \.isDefault) ?? current.first
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

    func setAccountPrefs(session: String, account: AccountInfo, role: String,
                         region: String?, profileName: String?) {
        do {
            try service.setAccountPrefs(session: session, accountId: account.accountId,
                                        accountName: account.name, role: role,
                                        region: region, profileName: profileName)
            reload()
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        notice = error.localizedDescription
    }
}
