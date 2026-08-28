import Foundation
import XCTest
@testable import AwseshCore

/// Deterministic in-memory SSO provider.
struct StubSSO: SSOProviding {
    var accounts: [Account] = [
        Account(accountId: "111111111111", name: "prod", roles: [], rolesLoaded: false),
        Account(accountId: "222222222222", name: "dev", roles: [], rolesLoaded: false),
    ]
    var rolesByAccount: [String: [String]] = [
        "111111111111": ["AdministratorAccess", "ReadOnly"],
        "222222222222": ["Developer"],
    ]
    var pollResults: [TokenResult?] = [nil, TokenResult(token: "tok", expiresAt: Date().addingTimeInterval(3600))]

    func startLogin(startUrl: String) async throws -> SSOLoginInfo {
        SSOLoginInfo(verificationUri: "https://device.sso", verificationUriComplete: "https://device.sso?code=ABCD",
                     userCode: "ABCD-EFGH", deviceCode: "dev-code", interval: 0, clientId: "cid",
                     clientSecret: "cs", expiresAt: Date().addingTimeInterval(600), startUrl: startUrl)
    }

    func pollForToken(_ info: SSOLoginInfo) async throws -> TokenResult? {
        StubSSO.pollCount += 1
        return pollResults[min(StubSSO.pollCount - 1, pollResults.count - 1)]
    }
    nonisolated(unsafe) static var pollCount = 0

    func listAccounts(token: String) async throws -> [Account] { accounts }
    func listRoles(token: String, accountId: String) async throws -> [String] { rolesByAccount[accountId] ?? [] }
    func getCredentials(token: String, accountId: String, roleName: String) async throws -> RoleCredentials {
        RoleCredentials(accessKeyId: "AKIA-\(accountId)", secretAccessKey: "sec", sessionToken: "st",
                        expiration: Date().addingTimeInterval(3600))
    }
}

final class AwseshServiceTests: XCTestCase {
    var service: AwseshService!
    var paths: AwseshPaths!

    override func setUpWithError() throws {
        StubSSO.pollCount = 0
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        paths = AwseshPaths(configDir: base.appending(path: "config"),
                            dataDir: base.appending(path: "data"),
                            awsDir: base.appending(path: "aws"))
        service = AwseshService(store: AwseshStore(paths: paths),
                                starred: StarredStore(directory: base.appending(path: "app")),
                                providerFactory: { _ in StubSSO() })
        try service.saveSession(SSOSession(name: "Elva", startUrl: "https://elva.awsapps.com/start",
                                           ssoRegion: "eu-north-1", defaultRegion: "eu-north-1"))
    }

    func signIn() throws {
        try service.store.saveToken(TokenCache(token: "tok", expiresAt: Date().addingTimeInterval(3600),
                                               startUrl: "https://elva.awsapps.com/start"))
    }

    func testSessionsReportAuthenticationState() throws {
        XCTAssertEqual(try service.sessions().map(\.authenticated), [false])
        try signIn()
        XCTAssertEqual(try service.sessions().map(\.authenticated), [true])
    }

    func testRefreshAccountsFetchesRolesAndCaches() async throws {
        try signIn()
        let accounts = try await service.refreshAccounts(session: "Elva")
        XCTAssertEqual(accounts.map(\.name), ["prod", "dev"])
        XCTAssertEqual(accounts[0].roles, ["AdministratorAccess", "ReadOnly"])
        // Cache persisted: readable without network.
        XCTAssertEqual(try service.accounts(session: "Elva").count, 2)
    }

    func testRefreshWithoutTokenThrowsNotSignedIn() async {
        do {
            _ = try await service.refreshAccounts(session: "Elva")
            XCTFail("expected notSignedIn")
        } catch let error as AwseshServiceError {
            guard case .notSignedIn = error else { return XCTFail("wrong error: \(error)") }
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testSetCredentialsUsesFallbacksAndRemembersRole() async throws {
        try signIn()
        _ = try await service.refreshAccounts(session: "Elva")
        let message = try await service.setCredentials(session: "Elva", account: "prod")
        XCTAssertTrue(message.contains("prod"))
        XCTAssertTrue(message.contains("AdministratorAccess")) // first role fallback

        // INI written with session default region
        let ini = try String(contentsOf: paths.awsDir.appending(path: "credentials"), encoding: .utf8)
        XCTAssertTrue(ini.contains("[default]"))
        XCTAssertTrue(ini.contains("region = eu-north-1"))

        // preferred role remembered; account lookup by name worked
        XCTAssertEqual(try service.store.preferredRoles(sessionName: "Elva")["111111111111"],
                       "AdministratorAccess")
        XCTAssertEqual(try service.current().first?.accountName, "prod")
        XCTAssertTrue(try XCTUnwrap(service.current().first).isDefault)
    }

    func testAwaitTokenPollsUntilApprovedAndSavesToken() async throws {
        let login = try await service.startLogin(session: "Elva")
        try await service.awaitToken(session: "Elva", login: login)
        XCTAssertEqual(StubSSO.pollCount, 2) // one pending, one success
        XCTAssertNotNil(try service.store.token(startUrl: "https://elva.awsapps.com/start"))
    }

    func testRemoveSessionClearsTokenCredentialsAndProfiles() async throws {
        try signIn()
        _ = try await service.refreshAccounts(session: "Elva")
        _ = try await service.setCredentials(session: "Elva", account: "dev")
        try service.removeSession(named: "Elva")

        XCTAssertTrue(try service.sessions().isEmpty)
        XCTAssertNil(try service.store.token(startUrl: "https://elva.awsapps.com/start"))
        XCTAssertTrue(try service.current().isEmpty)
        XCTAssertTrue(CredentialsFile.listProfiles(awsDir: paths.awsDir).isEmpty)
    }

    func testStarredRoundTrip() throws {
        try service.setStarred(true, session: "Elva", accountId: "111111111111")
        XCTAssertEqual(service.starred.starredIds(session: "Elva"), ["111111111111"])
        try service.setStarred(false, session: "Elva", accountId: "111111111111")
        XCTAssertTrue(service.starred.starredIds(session: "Elva").isEmpty)
    }

    func testPortalURLs() {
        XCTAssertEqual(SSOService.dashboardURL(startUrl: "https://x.awsapps.com/start/"),
                       "https://x.awsapps.com/start/#/?tab=accounts")
        XCTAssertEqual(SSOService.accountURL(startUrl: "https://x.awsapps.com/start",
                                             accountId: "1", roleName: "Admin"),
                       "https://x.awsapps.com/start/#/console?account_id=1&role_name=Admin")
    }
}

extension AwseshServiceTests {
    /// Regression: switching accounts on the default profile must leave
    /// exactly one active/default entry — the new one.
    func testSwitchingAccountsReplacesDefaultActiveEntry() async throws {
        try signIn()
        _ = try await service.refreshAccounts(session: "Elva")
        _ = try await service.setCredentials(session: "Elva", account: "prod")
        _ = try await service.setCredentials(session: "Elva", account: "dev")

        let current = try service.current()
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current[0].accountName, "dev")
        XCTAssertTrue(current[0].isDefault)
    }
}
