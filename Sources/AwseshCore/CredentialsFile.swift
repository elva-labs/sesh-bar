import Foundation

/// Reader/writer for the `~/.aws/credentials` INI file with the same
/// semantics as `@awsesh/core`: parse all sections, replace or remove one,
/// serialize everything back as `key = value` lines. Sections owned by other
/// tools are preserved verbatim in content (though not in formatting), which
/// matches the SDK's behavior exactly.
public enum CredentialsFile {

    public static func parse(_ content: String) -> [(section: String, values: [(String, String)])] {
        var sections: [(String, [(String, String)])] = []
        var current: (String, [(String, String)])? = nil

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                if let current { sections.append(current) }
                current = (String(line.dropFirst().dropLast()), [])
            } else if let eq = line.firstIndex(of: "="), current != nil {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                current?.1.append((key, value))
            }
        }
        if let current { sections.append(current) }
        return sections
    }

    public static func serialize(_ sections: [(section: String, values: [(String, String)])]) -> String {
        sections.map { section, values in
            "[\(section)]\n" + values.map { "\($0.0) = \($0.1)" }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    public static func write(profileName: String, credentials: RoleCredentials,
                             region: String?, awsDir: URL) throws {
        let path = awsDir.appending(path: "credentials")
        try FileManager.default.createDirectory(at: awsDir, withIntermediateDirectories: true)
        let content = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        var sections = parse(content).filter { $0.section != profileName }
        var values: [(String, String)] = [
            ("aws_access_key_id", credentials.accessKeyId),
            ("aws_secret_access_key", credentials.secretAccessKey),
            ("aws_session_token", credentials.sessionToken),
        ]
        if let region { values.append(("region", region)) }
        sections.append((profileName, values))
        try Data(serialize(sections).utf8).write(to: path, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    public static func removeProfile(_ profileName: String, awsDir: URL) throws {
        let path = awsDir.appending(path: "credentials")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return }
        let sections = parse(content)
        guard sections.contains(where: { $0.section == profileName }) else { return }
        let remaining = sections.filter { $0.section != profileName }
        let output = remaining.isEmpty ? "" : serialize(remaining)
        try Data(output.utf8).write(to: path, options: .atomic)
    }

    public static func listProfiles(awsDir: URL) -> [String] {
        let path = awsDir.appending(path: "credentials")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return parse(content).map(\.section)
    }
}
