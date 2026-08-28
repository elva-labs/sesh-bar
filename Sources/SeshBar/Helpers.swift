import AwseshCore
import SwiftUI

// Display helpers mirroring the Glaze app's renderer.

func initials(_ name: String) -> String {
    let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    let letters = parts.prefix(2).compactMap(\.first).map(String.init).joined()
    return (letters.isEmpty ? String(name.prefix(2)) : letters).uppercased()
}

func shortRole(_ role: String) -> String {
    var s = role
    if s.hasPrefix("AWS") { s.removeFirst(3) }
    if s.hasSuffix("Access") { s.removeLast(6) }
    return s.isEmpty ? role : s
}

func roleColor(_ role: String) -> Color {
    let lower = role.lowercased()
    if lower.contains("admin") { return .purple }
    if lower.contains("power") { return .teal }
    if lower.contains("readonly") || lower.contains("read-only") { return .blue }
    return .secondary
}

/// Lower rank = more privileged; picks the default role shown per account.
func roleRank(_ role: String) -> Int {
    let lower = role.lowercased()
    if lower.contains("admin") { return 0 }
    if lower.contains("power") { return 1 }
    if lower.contains("readonly") || lower.contains("read-only")
        || lower.contains("viewonly") || lower.contains("view-only") { return 3 }
    return 2
}

func defaultRole(for account: AccountInfo) -> String {
    if let preferred = account.preferredRole, account.roles.contains(preferred) { return preferred }
    return account.roles.sorted { roleRank($0) < roleRank($1) }.first ?? ""
}

struct ExpiryInfo {
    let label: String
    let tone: Color
}

func expiryInfo(iso: String?) -> ExpiryInfo? {
    guard let iso,
          let date = ISO8601DateFormatter.awseshLenient.dateLenient(from: iso) else { return nil }
    let remaining = date.timeIntervalSinceNow
    if remaining <= 0 { return ExpiryInfo(label: "Expired", tone: .red) }
    let mins = Int(remaining / 60)
    let label = mins >= 60 ? "\(mins / 60)h \(mins % 60)m left" : "\(mins)m left"
    let tone: Color = remaining < 15 * 60 ? .red : remaining < 60 * 60 ? .yellow : .green
    return ExpiryInfo(label: label, tone: tone)
}

func expiryInfo(date: Date?) -> ExpiryInfo? {
    guard let date else { return nil }
    return expiryInfo(iso: ISO8601DateFormatter.awseshMillis.string(from: date))
}
