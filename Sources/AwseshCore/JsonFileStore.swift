import Foundation

/// Minimal JSON-file key-value store mirroring `@awsesh/core`'s Storage:
/// a key like `"preference/last-session"` maps to `<root>/<key>.json`.
struct JsonFileStore: Sendable {
    let root: URL

    func url(for key: String) -> URL {
        root.appending(path: key + ".json")
    }

    func read<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        let fileURL = url(for: key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try AwseshJSON.decoder.decode(T.self, from: data)
    }

    func write<T: Encodable>(_ value: T, key: String) throws {
        let fileURL = url(for: key)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try AwseshJSON.encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }

    func remove(key: String) throws {
        let fileURL = url(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func exists(key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path)
    }

    /// Keys (without the .json suffix) under a prefix directory.
    func list(prefix: String) -> [String] {
        let dir = root.appending(path: prefix)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }
            .map { "\(prefix)/\($0.dropLast(5))" }
            .sorted()
    }
}
