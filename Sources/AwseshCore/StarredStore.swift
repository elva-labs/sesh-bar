import Foundation

/// Persisted set of starred accounts — a sesh-bar-only preference, not part
/// of the upstream awsesh data model. Same file format and key scheme
/// ("<session>::<accountId>") as the Glaze app used.
public final class StarredStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "starred-store")
    private var cache: [String: Bool]?

    public init(directory: URL) {
        self.fileURL = directory.appending(path: "starred-accounts.json")
    }

    /// Default location in this app's Application Support directory.
    public static func standard() -> StarredStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "sesh-bar")
        return StarredStore(directory: dir)
    }

    private func load() -> [String: Bool] {
        if let cache { return cache }
        let map = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
        cache = map
        return map
    }

    public func starredIds(session: String) -> Set<String> {
        queue.sync {
            let prefix = "\(session)::"
            return Set(load().keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
        }
    }

    public func setStarred(_ starred: Bool, session: String, accountId: String) throws {
        try queue.sync {
            var map = load()
            let key = "\(session)::\(accountId)"
            if starred { map[key] = true } else { map.removeValue(forKey: key) }
            cache = map
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try (try encoder.encode(map)).write(to: fileURL, options: .atomic)
        }
    }
}
