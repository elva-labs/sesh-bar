import CryptoKit
import Foundation

/// Token cache files are named by a 16-hex-character prefix of the SHA-256 of
/// the SSO start URL — the same derivation `@awsesh/core` uses, so both tools
/// resolve the same file for the same session.
public func startUrlHash(_ startUrl: String) -> String {
    let digest = SHA256.hash(data: Data(startUrl.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
}
