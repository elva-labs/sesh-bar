import Foundation

/// The network surface `AwseshService` needs — implemented by `SSOService`
/// (AWS SDK) in the app and by stubs in tests.
public protocol SSOProviding: Sendable {
    func startLogin(startUrl: String) async throws -> SSOLoginInfo
    func pollForToken(_ info: SSOLoginInfo) async throws -> TokenResult?
    func listAccounts(token: String) async throws -> [Account]
    func listRoles(token: String, accountId: String) async throws -> [String]
    func getCredentials(token: String, accountId: String, roleName: String) async throws -> RoleCredentials
}

extension SSOService: SSOProviding {}
