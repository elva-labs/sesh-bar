import Foundation

/// JSON en/decoding matched to `@awsesh/core`: dates serialize like JS
/// `Date.toISOString()` (millisecond precision, `Z` suffix) so files written
/// by either implementation parse in the other.
enum AwseshJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unparseable ISO 8601 date: \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var c = encoder.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        return e
    }()
}

public struct SSOSession: Codable, Hashable, Sendable {
    public var name: String
    public var startUrl: String
    public var ssoRegion: String
    public var defaultRegion: String
    public var isChina: Bool?

    public init(name: String, startUrl: String, ssoRegion: String, defaultRegion: String, isChina: Bool? = nil) {
        self.name = name
        self.startUrl = startUrl
        self.ssoRegion = ssoRegion
        self.defaultRegion = defaultRegion
        self.isChina = isChina
    }
}

public struct TokenCache: Codable, Hashable, Sendable {
    public var token: String
    public var expiresAt: Date
    public var startUrl: String

    public init(token: String, expiresAt: Date, startUrl: String) {
        self.token = token
        self.expiresAt = expiresAt
        self.startUrl = startUrl
    }

    public var isValid: Bool { expiresAt > Date() }
}

public struct Account: Codable, Hashable, Sendable {
    public var accountId: String
    public var name: String
    public var roles: [String]
    public var rolesLoaded: Bool
    public var region: String?

    public init(accountId: String, name: String, roles: [String], rolesLoaded: Bool, region: String? = nil) {
        self.accountId = accountId
        self.name = name
        self.roles = roles
        self.rolesLoaded = rolesLoaded
        self.region = region
    }
}

public struct AccountCache: Codable, Hashable, Sendable {
    public var accounts: [Account]
    /// Epoch milliseconds, as written by the JS SDK.
    public var lastUpdated: Double

    public init(accounts: [Account], lastUpdated: Double) {
        self.accounts = accounts
        self.lastUpdated = lastUpdated
    }
}

public struct RoleCredentials: Hashable, Sendable {
    public var accessKeyId: String
    public var secretAccessKey: String
    public var sessionToken: String
    public var expiration: Date

    public init(accessKeyId: String, secretAccessKey: String, sessionToken: String, expiration: Date) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }
}

public struct LastSelected: Codable, Hashable, Sendable {
    public var session: String?
    public var account: String?
    public var role: String?

    public init(session: String? = nil, account: String? = nil, role: String? = nil) {
        self.session = session
        self.account = account
        self.role = role
    }
}

public struct ActiveCredential: Codable, Hashable, Sendable {
    public var profileName: String
    public var accountId: String
    public var accountName: String
    public var roleName: String
    public var sessionName: String
    /// ISO string, kept as-is (matches the TS type, which is `string`).
    public var expiration: String
    public var isDefault: Bool
    public var region: String?

    public init(profileName: String, accountId: String, accountName: String, roleName: String,
                sessionName: String, expiration: String, isDefault: Bool, region: String? = nil) {
        self.profileName = profileName
        self.accountId = accountId
        self.accountName = accountName
        self.roleName = roleName
        self.sessionName = sessionName
        self.expiration = expiration
        self.isDefault = isDefault
        self.region = region
    }
}

public struct LastSetCredential: Codable, Hashable, Sendable {
    public var profileName: String
    public var accountId: String
    public var accountName: String
    public var roleName: String
    public var sessionName: String
    public var region: String?
    public var setAt: String

    public init(profileName: String, accountId: String, accountName: String, roleName: String,
                sessionName: String, region: String? = nil, setAt: String) {
        self.profileName = profileName
        self.accountId = accountId
        self.accountName = accountName
        self.roleName = roleName
        self.sessionName = sessionName
        self.region = region
        self.setAt = setAt
    }
}
