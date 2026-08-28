import Foundation

/// File-level façade over awsesh's shared state — the Swift counterpart of
/// `createAwsesh()` from `@awsesh/core`. Every read and write is byte-format
/// compatible with the JS SDK and the awsesh CLI.
public struct AwseshStore: Sendable {
    public let paths: AwseshPaths
    private let storage: JsonFileStore

    public init(paths: AwseshPaths = .standard()) {
        self.paths = paths
        self.storage = JsonFileStore(root: paths.storageDir)
    }

    // MARK: - Sessions (config dir)

    public func listSessions() throws -> [SSOSession] {
        let dir = paths.sessionsDir
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return try names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            let data = try Data(contentsOf: dir.appending(path: name))
            return try AwseshJSON.decoder.decode(SSOSession.self, from: data)
        }
    }

    public func session(named name: String) throws -> SSOSession? {
        try listSessions().first { $0.name == name }
    }

    public func saveSession(_ session: SSOSession) throws {
        try FileManager.default.createDirectory(at: paths.sessionsDir, withIntermediateDirectories: true)
        let data = try AwseshJSON.encoder.encode(session)
        try data.write(to: paths.sessionsDir.appending(path: "\(session.name).json"), options: .atomic)
    }

    public func removeSession(named name: String) throws {
        let url = paths.sessionsDir.appending(path: "\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Token cache

    public func token(startUrl: String) throws -> TokenCache? {
        try storage.read(TokenCache.self, key: "token/\(startUrlHash(startUrl))")
    }

    public func saveToken(_ cache: TokenCache) throws {
        try storage.write(cache, key: "token/\(startUrlHash(cache.startUrl))")
    }

    public func removeToken(startUrl: String) throws {
        try storage.remove(key: "token/\(startUrlHash(startUrl))")
    }

    // MARK: - Account cache

    public func accountCache(sessionName: String) throws -> AccountCache? {
        try storage.read(AccountCache.self, key: "accounts/\(sessionName)")
    }

    public func saveAccountCache(_ cache: AccountCache, sessionName: String) throws {
        try storage.write(cache, key: "accounts/\(sessionName)")
    }

    // MARK: - Preferences

    public func lastSelected() throws -> LastSelected {
        try storage.read(LastSelected.self, key: "preference/last-selected") ?? LastSelected()
    }

    public func saveLastSelected(_ value: LastSelected) throws {
        try storage.write(value, key: "preference/last-selected")
    }

    public func lastSession() throws -> String? {
        struct Wrapper: Codable { var session: String? }
        return try storage.read(Wrapper.self, key: "preference/last-session")?.session
    }

    public func saveLastSession(_ name: String) throws {
        struct Wrapper: Codable { var session: String? }
        try storage.write(Wrapper(session: name), key: "preference/last-session")
    }

    public func lastAccount(sessionName: String) throws -> String? {
        try (storage.read([String: String].self, key: "preference/last-accounts") ?? [:])[sessionName]
    }

    public func saveLastAccount(_ accountId: String, sessionName: String) throws {
        var map = try storage.read([String: String].self, key: "preference/last-accounts") ?? [:]
        map[sessionName] = accountId
        try storage.write(map, key: "preference/last-accounts")
    }

    public func preferredRoles(sessionName: String) throws -> [String: String] {
        try (storage.read([String: [String: String]].self, key: "preference/preferred-roles") ?? [:])[sessionName] ?? [:]
    }

    public func savePreferredRole(_ roleName: String, sessionName: String, accountId: String) throws {
        var map = try storage.read([String: [String: String]].self, key: "preference/preferred-roles") ?? [:]
        map[sessionName, default: [:]][accountId] = roleName
        try storage.write(map, key: "preference/preferred-roles")
    }

    public func preferredRegions(sessionName: String) throws -> [String: String] {
        try (storage.read([String: [String: String]].self, key: "preference/preferred-regions") ?? [:])[sessionName] ?? [:]
    }

    public func savePreferredRegion(_ region: String, sessionName: String, accountId: String) throws {
        var map = try storage.read([String: [String: String]].self, key: "preference/preferred-regions") ?? [:]
        map[sessionName, default: [:]][accountId] = region
        try storage.write(map, key: "preference/preferred-regions")
    }

    public func profileName(sessionName: String, accountName: String, roleName: String) throws -> String? {
        let map = try storage.read([String: [String: [String: String]]].self, key: "preference/profile-names") ?? [:]
        return map[sessionName]?[accountName]?[roleName]
    }

    public func saveProfileName(_ profileName: String, sessionName: String, accountName: String, roleName: String) throws {
        var map = try storage.read([String: [String: [String: String]]].self, key: "preference/profile-names") ?? [:]
        map[sessionName, default: [:]][accountName, default: [:]][roleName] = profileName
        try storage.write(map, key: "preference/profile-names")
    }

    // MARK: - Active credentials tracking

    public func activeCredentials() throws -> [ActiveCredential] {
        var list = try storage.read([ActiveCredential].self, key: "credentials/active") ?? []
        // Drop expired entries on read, like the SDK's cleanup.
        let now = Date()
        list = list.filter { entry in
            guard let date = ISO8601DateFormatter.awseshLenient.dateLenient(from: entry.expiration) else { return true }
            return date > now
        }
        return list
    }

    public func saveActiveCredential(_ credential: ActiveCredential) throws {
        var list = try storage.read([ActiveCredential].self, key: "credentials/active") ?? []
        list.removeAll { $0.accountId == credential.accountId && $0.roleName == credential.roleName }
        list.append(credential)
        try storage.write(list, key: "credentials/active")
    }

    public func removeActiveCredential(accountId: String, roleName: String) throws {
        var list = try storage.read([ActiveCredential].self, key: "credentials/active") ?? []
        list.removeAll { $0.accountId == accountId && $0.roleName == roleName }
        try storage.write(list, key: "credentials/active")
    }

    public func lastSetCredential() throws -> LastSetCredential? {
        try storage.read(LastSetCredential.self, key: "credentials/last-set")
    }

    public func saveLastSetCredential(_ credential: LastSetCredential) throws {
        try storage.write(credential, key: "credentials/last-set")
    }

    public func clearLastSetCredential() throws {
        try storage.remove(key: "credentials/last-set")
    }

    // MARK: - High-level credential operations

    public struct SetCredentialResult: Sendable {
        public let profileName: String
        public let expiration: Date
        public let isDefault: Bool
    }

    /// Write role credentials to `~/.aws/credentials` and update all tracking
    /// state, mirroring the SDK's `setCredential()`.
    public func setCredential(_ credentials: RoleCredentials, sessionName: String, accountId: String,
                              accountName: String, roleName: String, region: String? = nil,
                              profileName explicitProfile: String? = nil) throws -> SetCredentialResult {
        let profileName = try explicitProfile
            ?? self.profileName(sessionName: sessionName, accountName: accountName, roleName: roleName)
            ?? "default"

        try CredentialsFile.write(profileName: profileName, credentials: credentials,
                                  region: region, awsDir: paths.awsDir)

        let iso = ISO8601DateFormatter.awseshMillis
        try saveActiveCredential(ActiveCredential(
            profileName: profileName, accountId: accountId, accountName: accountName,
            roleName: roleName, sessionName: sessionName,
            expiration: iso.string(from: credentials.expiration),
            isDefault: profileName == "default", region: region))
        try saveLastSetCredential(LastSetCredential(
            profileName: profileName, accountId: accountId, accountName: accountName,
            roleName: roleName, sessionName: sessionName, region: region,
            setAt: iso.string(from: Date())))
        try saveLastSelected(LastSelected(session: sessionName, account: accountId, role: roleName))
        try saveLastSession(sessionName)
        try saveLastAccount(accountId, sessionName: sessionName)

        return SetCredentialResult(profileName: profileName,
                                   expiration: credentials.expiration,
                                   isDefault: profileName == "default")
    }

    public func clearCredential(accountId: String, roleName: String, removeProfile: String? = nil) throws {
        try removeActiveCredential(accountId: accountId, roleName: roleName)
        if let removeProfile {
            try CredentialsFile.removeProfile(removeProfile, awsDir: paths.awsDir)
        }
        if let last = try lastSetCredential(), last.accountId == accountId, last.roleName == roleName {
            try clearLastSetCredential()
        }
    }

    public func clearSessionCredentials(sessionName: String, removeProfiles: Bool = false) throws {
        let matching = try (storage.read([ActiveCredential].self, key: "credentials/active") ?? [])
            .filter { $0.sessionName == sessionName }
        for entry in matching {
            try clearCredential(accountId: entry.accountId, roleName: entry.roleName,
                                removeProfile: removeProfiles ? entry.profileName : nil)
        }
    }
}

extension ISO8601DateFormatter {
    static let awseshMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let awseshLenient = ISO8601DateFormatter()

    func dateLenient(from string: String) -> Date? {
        ISO8601DateFormatter.awseshMillis.date(from: string)
            ?? ISO8601DateFormatter.awseshLenient.date(from: string)
    }
}
