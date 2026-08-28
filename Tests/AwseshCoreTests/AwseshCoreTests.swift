import Foundation
import XCTest
@testable import AwseshCore

final class StartUrlHashTests: XCTestCase {
    func testMatchesJsSdkDerivation() {
        // Vector computed with the JS SDK's derivation (sha256 hex, first 16).
        XCTAssertEqual(startUrlHash("https://example.awsapps.com/start"), "37810fd848c76dec")
    }
}

final class CredentialsFileTests: XCTestCase {
    func testParseSerializeRoundTrip() {
        let input = """
        [default]
        aws_access_key_id = AKIAEXAMPLE
        aws_secret_access_key = secret
        aws_session_token = tok

        [other-tool]
        aws_access_key_id = AKIAOTHER
        region = eu-north-1
        """
        let sections = CredentialsFile.parse(input)
        XCTAssertEqual(sections.map(\.section), ["default", "other-tool"])
        let out = CredentialsFile.serialize(sections)
        XCTAssertTrue(out.contains("[other-tool]\naws_access_key_id = AKIAOTHER\nregion = eu-north-1"))
        XCTAssertTrue(out.hasSuffix("\n"))
    }

    func testWritePreservesForeignSectionsAndReplacesOwn() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let creds = RoleCredentials(accessKeyId: "AKIA1", secretAccessKey: "S1",
                                    sessionToken: "T1", expiration: Date())
        let existing = "[keep-me]\naws_access_key_id = AKIAKEEP\n\n[dev]\naws_access_key_id = OLD\n"
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(existing.utf8).write(to: dir.appending(path: "credentials"))

        try CredentialsFile.write(profileName: "dev", credentials: creds, region: "eu-north-1", awsDir: dir)

        let content = try String(contentsOf: dir.appending(path: "credentials"), encoding: .utf8)
        XCTAssertTrue(content.contains("[keep-me]"))
        XCTAssertTrue(content.contains("aws_access_key_id = AKIAKEEP"))
        XCTAssertTrue(content.contains("[dev]"))
        XCTAssertTrue(content.contains("aws_access_key_id = AKIA1"))
        XCTAssertTrue(content.contains("region = eu-north-1"))
        XCTAssertFalse(content.contains("OLD"))
        XCTAssertEqual(CredentialsFile.listProfiles(awsDir: dir), ["keep-me", "dev"])

        try CredentialsFile.removeProfile("dev", awsDir: dir)
        XCTAssertEqual(CredentialsFile.listProfiles(awsDir: dir), ["keep-me"])
    }
}

final class AwseshStoreCompatTests: XCTestCase {
    var paths: AwseshPaths!
    var store: AwseshStore!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        paths = AwseshPaths(configDir: base.appending(path: "config"),
                            dataDir: base.appending(path: "data"),
                            awsDir: base.appending(path: "aws"))
        store = AwseshStore(paths: paths)
    }

    /// Fixtures below are byte-shaped like real files written by @awsesh/core.
    func write(_ json: String, to relative: String) throws {
        let url = paths.dataDir.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    func testReadsJsWrittenSessionFile() throws {
        let dir = paths.sessionsDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"name":"Acme Corp","startUrl":"https://acme.awsapps.com/start","ssoRegion":"eu-north-1","defaultRegion":"eu-north-1"}"#.utf8)
            .write(to: dir.appending(path: "Acme Corp.json"))
        let sessions = try store.listSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].name, "Acme Corp")
        XCTAssertEqual(sessions[0].ssoRegion, "eu-north-1")
    }

    func testTokenCacheRoundTripsWithJsDateFormat() throws {
        try write(#"{"token":"tok-123","expiresAt":"2027-01-02T03:04:05.678Z","startUrl":"https://acme.awsapps.com/start"}"#,
                  to: "storage/token/\(startUrlHash("https://acme.awsapps.com/start")).json")
        let cache = try XCTUnwrap(store.token(startUrl: "https://acme.awsapps.com/start"))
        XCTAssertEqual(cache.token, "tok-123")
        XCTAssertTrue(cache.isValid)

        // Re-save and confirm the file keeps the JS millisecond ISO format.
        try store.saveToken(cache)
        let data = try Data(contentsOf: paths.dataDir.appending(
            path: "storage/token/\(startUrlHash("https://acme.awsapps.com/start")).json"))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["expiresAt"] as? String, "2027-01-02T03:04:05.678Z")
    }

    func testPreferencesMatchObservedShapes() throws {
        try write(#"{"Elva":{"169634836316":"AdministratorAccess"}}"#, to: "storage/preference/preferred-roles.json")
        try write(#"{"Elva":"123456789012"}"#, to: "storage/preference/last-accounts.json")
        try write(#"{"session":"Elva"}"#, to: "storage/preference/last-session.json")
        try write(#"{"session":"Elva","account":"123456789012","role":"AdministratorAccess"}"#,
                  to: "storage/preference/last-selected.json")

        XCTAssertEqual(try store.preferredRoles(sessionName: "Elva")["169634836316"], "AdministratorAccess")
        XCTAssertEqual(try store.lastAccount(sessionName: "Elva"), "123456789012")
        XCTAssertEqual(try store.lastSession(), "Elva")
        XCTAssertEqual(try store.lastSelected().role, "AdministratorAccess")
    }

    func testSetCredentialWritesIniAndAllTrackingState() throws {
        let expiry = Date().addingTimeInterval(3600)
        let result = try store.setCredential(
            RoleCredentials(accessKeyId: "AKIA1", secretAccessKey: "S", sessionToken: "T", expiration: expiry),
            sessionName: "Elva", accountId: "123456789012", accountName: "prod",
            roleName: "AdministratorAccess", region: "eu-north-1")

        XCTAssertEqual(result.profileName, "default")
        XCTAssertTrue(result.isDefault)
        XCTAssertEqual(CredentialsFile.listProfiles(awsDir: paths.awsDir), ["default"])

        let active = try store.activeCredentials()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].accountId, "123456789012")
        XCTAssertEqual(try store.lastSetCredential()?.roleName, "AdministratorAccess")
        XCTAssertEqual(try store.lastSelected().session, "Elva")
        XCTAssertEqual(try store.lastSession(), "Elva")

        try store.clearCredential(accountId: "123456789012", roleName: "AdministratorAccess",
                                  removeProfile: "default")
        XCTAssertTrue(try store.activeCredentials().isEmpty)
        XCTAssertNil(try store.lastSetCredential())
        XCTAssertTrue(CredentialsFile.listProfiles(awsDir: paths.awsDir).isEmpty)
    }

    func testExpiredActiveCredentialsAreDroppedOnRead() throws {
        try write(#"[{"profileName":"default","accountId":"1","accountName":"a","roleName":"r","sessionName":"s","expiration":"2020-01-01T00:00:00.000Z","isDefault":true}]"#,
                  to: "storage/credentials/active.json")
        XCTAssertTrue(try store.activeCredentials().isEmpty)
    }
}

/// Opt-in: decodes the REAL awsesh files on this machine, read-only.
///   AWSESH_REAL=1 swift test
final class RealFilesCompatTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AWSESH_REAL"] == "1")
    }

    func testRealFilesDecode() throws {
        let store = AwseshStore(paths: .standard())
        let sessions = try store.listSessions()
        print("real sessions:", sessions.map(\.name))
        for session in sessions {
            _ = try store.token(startUrl: session.startUrl)          // decodes or nil
            _ = try store.accountCache(sessionName: session.name)    // decodes or nil
        }
        _ = try store.lastSelected()
        _ = try store.lastSession()
        _ = try store.activeCredentials()
        XCTAssertFalse(sessions.isEmpty, "expected at least one real session")
    }
}
