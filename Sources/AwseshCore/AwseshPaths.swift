import Foundation

/// The three directories shared with the `awsesh` CLI and other frontends.
/// All tools read and write the same files, so the layout is contract, not
/// implementation detail.
public struct AwseshPaths: Sendable {
    /// SSO session definitions: `<configDir>/sessions/<Name>.json`
    public let configDir: URL
    /// Caches and preferences: `<dataDir>/storage/<area>/<key>.json`
    public let dataDir: URL
    /// The AWS shared config directory holding the `credentials` INI file.
    public let awsDir: URL

    public init(configDir: URL, dataDir: URL, awsDir: URL) {
        self.configDir = configDir
        self.dataDir = dataDir
        self.awsDir = awsDir
    }

    /// awsesh's default locations (XDG-style, matching the CLI and SDK).
    public static func standard() -> AwseshPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AwseshPaths(
            configDir: home.appending(path: ".config/awsesh"),
            dataDir: home.appending(path: ".local/share/awsesh"),
            awsDir: home.appending(path: ".aws")
        )
    }

    public var sessionsDir: URL { configDir.appending(path: "sessions") }
    public var storageDir: URL { dataDir.appending(path: "storage") }
}
