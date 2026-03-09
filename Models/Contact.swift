import Foundation
import GRDB

struct Contact: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "contacts"

    /// Elysium node ID (sha256 fingerprint).
    var nodeId: String
    var displayName: String
    /// Base64-encoded Curve25519 public key — used for E2E encryption.
    var publicKey: String
    var addedAt: Date

    // Identifiable conformance — nodeId is the stable identity.
    var id: String { nodeId }

    /// Deterministic avatar colour derived from the node ID.
    var avatarColor: String {
        let hash = abs(nodeId.hashValue)
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
                      "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
                      "#BB8FCE", "#82E0AA"]
        return colors[hash % colors.count]
    }

    /// Truncated ID for display.
    var shortId: String {
        nodeId.count > 16 ? String(nodeId.prefix(8)) + "…" + String(nodeId.suffix(8)) : nodeId
    }
}
