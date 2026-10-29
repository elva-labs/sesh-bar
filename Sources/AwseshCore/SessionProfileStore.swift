import Foundation

/// Persisted CLI profile per SSO session — a sesh-bar-only preference, not
/// part of the upstream awsesh data model (the CLI rewrites session files
/// from its own form, so an extra field there wouldn't survive). Sessions
/// without an entry write to `[default]`.
public final class SessionProfileStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "session-profile-store")
    private var cache: [String: String]?

    public init(directory: URL) {
        self.fileURL = directory.appending(path: "session-profiles.json")
    }

    /// Default location in this app's Application Support directory.
    public static func standard() -> SessionProfileStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "sesh-bar")
        return SessionProfileStore(directory: dir)
    }

    private func load() -> [String: String] {
        if let cache { return cache }
        let map = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        cache = map
        return map
    }

    /// The session's profile, or nil when it uses `[default]`.
    public func profile(session: String) -> String? {
        queue.sync { load()[session] }
    }

    /// Nil, empty or "default" clears the entry.
    public func setProfile(_ profile: String?, session: String) throws {
        try queue.sync {
            var map = load()
            let trimmed = profile?.trimmingCharacters(in: .whitespaces) ?? ""
            if trimmed.isEmpty || trimmed == "default" {
                guard map.removeValue(forKey: session) != nil else { return }
            } else {
                map[session] = trimmed
            }
            cache = map
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try (try encoder.encode(map)).write(to: fileURL, options: .atomic)
        }
    }
}
