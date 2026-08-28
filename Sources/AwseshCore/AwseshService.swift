import Foundation

/// UI-facing view models, mirroring the shapes the Glaze app exposed over IPC.
public struct SessionInfo: Hashable, Sendable {
    public let name: String
    public let startUrl: String
    public let ssoRegion: String
    public let defaultRegion: String
    public let authenticated: Bool
    public let tokenExpires: Date?
}

public struct AccountInfo: Hashable, Sendable, Identifiable {
    public let accountId: String
    public let name: String
    public let roles: [String]
    public let preferredRole: String?
    public let preferredRegion: String?
    public let profileNames: [String: String]
    public let starred: Bool
    public var id: String { accountId }
}

public struct CredentialInfo: Hashable, Sendable {
    public let profileName: String
    public let accountId: String
    public let accountName: String
    public let roleName: String
    public let sessionName: String
    public let expiration: String?
    public let isDefault: Bool
    public let region: String?
}

public enum AwseshServiceError: LocalizedError {
    case unknownSession(String)
    case notSignedIn(String)
    case unknownAccount(String)
    case noRole(String)
    case loginTimedOut(String)
    case nothingActive

    public var errorDescription: String? {
        switch self {
        case .unknownSession(let name): return "Unknown awsesh session: \(name)"
        case .notSignedIn(let name): return "Not signed in to \(name). Sign in first."
        case .unknownAccount(let name): return "Unknown account: \(name)"
        case .noRole(let account): return "No role available for \(account)"
        case .loginTimedOut(let name): return "Sign-in to \(name) timed out or was denied"
        case .nothingActive: return "No active AWS session"
        }
    }
}

/// Orchestrates store + SSO network calls with the same behavior as the
/// Glaze app's `main/services/awsesh.ts`.
public struct AwseshService: Sendable {
    public let store: AwseshStore
    public let starred: StarredStore
    let providerFactory: @Sendable (String) -> any SSOProviding

    public init(store: AwseshStore = AwseshStore(),
                starred: StarredStore = .standard(),
                providerFactory: @escaping @Sendable (String) -> any SSOProviding = { SSOService(region: $0) }) {
        self.store = store
        self.starred = starred
        self.providerFactory = providerFactory
    }

    // MARK: - Reads (no network)

    public func sessions() throws -> [SessionInfo] {
        try store.listSessions().map { session in
            let token = try? store.token(startUrl: session.startUrl)
            return SessionInfo(name: session.name, startUrl: session.startUrl,
                               ssoRegion: session.ssoRegion, defaultRegion: session.defaultRegion,
                               authenticated: token != nil,
                               tokenExpires: token?.expiresAt)
        }
    }

    public func current() throws -> [CredentialInfo] {
        try store.activeCredentials().map { cred in
            CredentialInfo(profileName: cred.profileName, accountId: cred.accountId,
                           accountName: cred.accountName, roleName: cred.roleName,
                           sessionName: cred.sessionName, expiration: cred.expiration,
                           isDefault: cred.isDefault || cred.profileName == "default",
                           region: cred.region)
        }
    }

    public func accounts(session: String) throws -> [AccountInfo] {
        let cached = try store.accountCache(sessionName: session)?.accounts ?? []
        let roles = try store.preferredRoles(sessionName: session)
        let regions = try store.preferredRegions(sessionName: session)
        let starredIds = starred.starredIds(session: session)
        return try cached.map { account in
            var profiles: [String: String] = [:]
            for role in account.roles {
                if let p = try store.profileName(sessionName: session, accountName: account.name, roleName: role) {
                    profiles[role] = p
                }
            }
            return AccountInfo(accountId: account.accountId, name: account.name, roles: account.roles,
                               preferredRole: roles[account.accountId],
                               preferredRegion: regions[account.accountId],
                               profileNames: profiles,
                               starred: starredIds.contains(account.accountId))
        }
    }

    // MARK: - Network operations

    /// Refresh a session's accounts (and each account's roles) from AWS,
    /// then persist the cache. Returns the merged view.
    public func refreshAccounts(session sessionName: String) async throws -> [AccountInfo] {
        let session = try requireSession(sessionName)
        let token = try requireToken(session)
        let provider = providerFactory(session.ssoRegion)
        var accounts = try await provider.listAccounts(token: token.token)
        for i in accounts.indices where !accounts[i].rolesLoaded {
            accounts[i].roles = try await provider.listRoles(token: token.token, accountId: accounts[i].accountId)
            accounts[i].rolesLoaded = true
        }
        try store.saveAccountCache(AccountCache(accounts: accounts,
                                                lastUpdated: Date().timeIntervalSince1970 * 1000),
                                   sessionName: sessionName)
        return try self.accounts(session: sessionName)
    }

    /// Switch the default AWS profile to the given account/role.
    /// Role and region fall back to preferences, then to the account's first
    /// role / the session's default region — exactly like the Glaze app.
    @discardableResult
    public func setCredentials(session sessionName: String, account accountRef: String,
                               role: String? = nil, region: String? = nil) async throws -> String {
        let session = try requireSession(sessionName)
        let token = try requireToken(session)
        let cached = try store.accountCache(sessionName: sessionName)?.accounts ?? []
        guard let account = cached.first(where: { $0.accountId == accountRef || $0.name == accountRef }) else {
            throw AwseshServiceError.unknownAccount(accountRef)
        }
        let roleName = try role
            ?? store.preferredRoles(sessionName: sessionName)[account.accountId]
            ?? account.roles.first
        guard let roleName else { throw AwseshServiceError.noRole(account.name) }

        let resolvedRegion = try region
            ?? store.preferredRegions(sessionName: sessionName)[account.accountId]
            ?? session.defaultRegion
        let profileName = try store.profileName(sessionName: sessionName,
                                                accountName: account.name, roleName: roleName)

        let provider = providerFactory(session.ssoRegion)
        let credentials = try await provider.getCredentials(token: token.token,
                                                            accountId: account.accountId,
                                                            roleName: roleName)
        let result = try store.setCredential(credentials, sessionName: sessionName,
                                             accountId: account.accountId, accountName: account.name,
                                             roleName: roleName, region: resolvedRegion,
                                             profileName: profileName)
        try store.savePreferredRole(roleName, sessionName: sessionName, accountId: account.accountId)
        return "Switched to \(account.name) (\(roleName)) — profile \"\(result.profileName)\""
    }

    /// Begin the device-code sign-in. The caller shows `userCode` and opens
    /// `verificationUriComplete`, then calls `awaitToken`.
    public func startLogin(session sessionName: String) async throws -> SSOLoginInfo {
        let session = try requireSession(sessionName)
        return try await providerFactory(session.ssoRegion).startLogin(startUrl: session.startUrl)
    }

    /// Poll until the user approves in the browser, the device code expires,
    /// or the task is cancelled. Persists the token on success.
    public func awaitToken(session sessionName: String, login: SSOLoginInfo) async throws {
        let session = try requireSession(sessionName)
        let provider = providerFactory(session.ssoRegion)
        while Date() < login.expiresAt {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(login.interval) * 1_000_000_000)
            if let result = try await provider.pollForToken(login) {
                try store.saveToken(TokenCache(token: result.token,
                                               expiresAt: result.expiresAt,
                                               startUrl: session.startUrl))
                return
            }
        }
        throw AwseshServiceError.loginTimedOut(sessionName)
    }

    // MARK: - Session management

    public func saveSession(_ session: SSOSession) throws {
        try store.saveSession(session)
    }

    /// Remove a session along with its token and tracked credentials/profiles.
    public func removeSession(named name: String) throws {
        let session = try? store.session(named: name)
        try store.clearSessionCredentials(sessionName: name, removeProfiles: true)
        if let session { try store.removeToken(startUrl: session.startUrl) }
        try store.removeSession(named: name)
    }

    public func signOut(session name: String) throws {
        let session = try requireSession(name)
        try store.removeToken(startUrl: session.startUrl)
        try store.clearSessionCredentials(sessionName: name, removeProfiles: true)
    }

    /// Unset the active default profile without touching other sessions.
    public func clearActive() throws -> [CredentialInfo] {
        let list = try current()
        if let active = list.first(where: \.isDefault) ?? list.first {
            try store.clearCredential(accountId: active.accountId, roleName: active.roleName,
                                      removeProfile: active.profileName)
        }
        return try current()
    }

    /// The console URL for the active credential (or the dashboard when the
    /// session has no valid token).
    public func consoleURL() throws -> URL {
        let list = try current()
        guard let active = list.first(where: \.isDefault) ?? list.first else {
            throw AwseshServiceError.nothingActive
        }
        let session = try requireSession(active.sessionName)
        let urlString: String
        if (try? store.token(startUrl: session.startUrl)) != nil {
            urlString = SSOService.accountURL(startUrl: session.startUrl,
                                              accountId: active.accountId,
                                              roleName: active.roleName)
        } else {
            urlString = SSOService.dashboardURL(startUrl: session.startUrl)
        }
        guard let url = URL(string: urlString) else { throw AwseshServiceError.nothingActive }
        return url
    }

    // MARK: - Preferences

    public func setStarred(_ value: Bool, session: String, accountId: String) throws {
        try starred.setStarred(value, session: session, accountId: accountId)
    }

    public func setAccountPrefs(session: String, accountId: String, accountName: String,
                                role: String, region: String?, profileName: String?) throws {
        if let region, !region.isEmpty {
            try store.savePreferredRegion(region, sessionName: session, accountId: accountId)
        }
        if let profileName {
            // Empty string clears the custom profile name, mirroring the Glaze app.
            try store.saveProfileName(profileName, sessionName: session,
                                      accountName: accountName, roleName: role)
        }
    }

    // MARK: - Helpers

    func requireSession(_ name: String) throws -> SSOSession {
        guard let session = try store.session(named: name) else {
            throw AwseshServiceError.unknownSession(name)
        }
        return session
    }

    func requireToken(_ session: SSOSession) throws -> TokenCache {
        guard let token = try store.token(startUrl: session.startUrl) else {
            throw AwseshServiceError.notSignedIn(session.name)
        }
        return token
    }
}
