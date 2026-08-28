import AWSSSO
import AWSSSOOIDC
import Foundation

public struct SSOLoginInfo: Sendable {
    public let verificationUri: String
    public let verificationUriComplete: String
    public let userCode: String
    public let deviceCode: String
    /// Seconds between CreateToken polls, as instructed by the service.
    public let interval: Int
    public let clientId: String
    public let clientSecret: String
    public let expiresAt: Date
    public let startUrl: String
}

public struct TokenResult: Sendable {
    public let token: String
    public let expiresAt: Date
}

public enum SSOServiceError: LocalizedError {
    case deviceCodeExpired
    case missingField(String)
    case noCredentials(accountId: String, roleName: String)

    public var errorDescription: String? {
        switch self {
        case .deviceCodeExpired:
            return "Device code expired — please try signing in again."
        case .missingField(let name):
            return "AWS response was missing \(name)."
        case .noCredentials(let accountId, let roleName):
            return "No credentials returned for \(accountId)/\(roleName)."
        }
    }
}

/// AWS SSO / SSO-OIDC operations, mirroring `@awsesh/core`'s AWSClient:
/// public-client device-code flow (registered as "awsesh", so AWS-side
/// grants look identical across the CLI, the Glaze app, and this app),
/// paginated account/role listing, and role-credential fetch.
public struct SSOService: Sendable {
    public let region: String

    public init(region: String) {
        self.region = region
    }

    private func oidcClient() throws -> SSOOIDCClient {
        try SSOOIDCClient(region: region)
    }

    private func ssoClient() throws -> SSOClient {
        try SSOClient(region: region)
    }

    // MARK: - Device-code login

    public func startLogin(startUrl: String) async throws -> SSOLoginInfo {
        let oidc = try oidcClient()
        let registration = try await oidc.registerClient(input: RegisterClientInput(
            clientName: "awsesh", clientType: "public"))
        guard let clientId = registration.clientId,
              let clientSecret = registration.clientSecret else {
            throw SSOServiceError.missingField("client registration")
        }
        let device = try await oidc.startDeviceAuthorization(input: StartDeviceAuthorizationInput(
            clientId: clientId, clientSecret: clientSecret, startUrl: startUrl))
        return SSOLoginInfo(
            verificationUri: device.verificationUri ?? "",
            verificationUriComplete: device.verificationUriComplete ?? "",
            userCode: device.userCode ?? "",
            deviceCode: device.deviceCode ?? "",
            interval: device.interval == 0 ? 5 : device.interval,
            clientId: clientId,
            clientSecret: clientSecret,
            expiresAt: Date().addingTimeInterval(TimeInterval(device.expiresIn == 0 ? 600 : device.expiresIn)),
            startUrl: startUrl)
    }

    /// One poll attempt. Returns nil while the user hasn't finished the
    /// browser flow yet (authorization pending / slow down), a token once
    /// approved, and throws when the device code has expired.
    public func pollForToken(_ info: SSOLoginInfo) async throws -> TokenResult? {
        let oidc = try oidcClient()
        do {
            let response = try await oidc.createToken(input: CreateTokenInput(
                clientId: info.clientId,
                clientSecret: info.clientSecret,
                deviceCode: info.deviceCode,
                grantType: "urn:ietf:params:oauth:grant-type:device_code"))
            guard let token = response.accessToken else { return nil }
            let expiresIn = response.expiresIn == 0 ? 28800 : response.expiresIn
            return TokenResult(token: token, expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)))
        } catch is AuthorizationPendingException {
            return nil
        } catch is SlowDownException {
            return nil
        } catch is ExpiredTokenException {
            throw SSOServiceError.deviceCodeExpired
        }
    }

    // MARK: - Accounts & roles

    public func listAccounts(token: String) async throws -> [Account] {
        let sso = try ssoClient()
        var accounts: [Account] = []
        var nextToken: String? = nil
        repeat {
            let response = try await sso.listAccounts(input: ListAccountsInput(
                accessToken: token, nextToken: nextToken))
            for item in response.accountList ?? [] {
                accounts.append(Account(
                    accountId: item.accountId ?? "",
                    name: item.accountName ?? "",
                    roles: [], rolesLoaded: false))
            }
            nextToken = response.nextToken
        } while nextToken != nil
        return accounts.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    public func listRoles(token: String, accountId: String) async throws -> [String] {
        let sso = try ssoClient()
        var roles: [String] = []
        var nextToken: String? = nil
        repeat {
            let response = try await sso.listAccountRoles(input: ListAccountRolesInput(
                accessToken: token, accountId: accountId, nextToken: nextToken))
            roles.append(contentsOf: (response.roleList ?? []).compactMap(\.roleName))
            nextToken = response.nextToken
        } while nextToken != nil
        return roles.sorted()
    }

    public func getCredentials(token: String, accountId: String, roleName: String) async throws -> RoleCredentials {
        let sso = try ssoClient()
        let response = try await sso.getRoleCredentials(input: GetRoleCredentialsInput(
            accessToken: token, accountId: accountId, roleName: roleName))
        guard let creds = response.roleCredentials else {
            throw SSOServiceError.noCredentials(accountId: accountId, roleName: roleName)
        }
        return RoleCredentials(
            accessKeyId: creds.accessKeyId ?? "",
            secretAccessKey: creds.secretAccessKey ?? "",
            sessionToken: creds.sessionToken ?? "",
            expiration: Date(timeIntervalSince1970: TimeInterval(creds.expiration) / 1000))
    }

    // MARK: - Portal URLs (pure)

    public static func dashboardURL(startUrl: String) -> String {
        "\(portalBase(startUrl))/start/#/?tab=accounts"
    }

    public static func accountURL(startUrl: String, accountId: String, roleName: String) -> String {
        "\(portalBase(startUrl))/start/#/console?account_id=\(accountId)&role_name=\(roleName)"
    }

    private static func portalBase(_ startUrl: String) -> String {
        var base = startUrl
        if base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/start") { base.removeLast("/start".count) }
        return base
    }
}
