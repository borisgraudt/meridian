import Foundation
import GRDB

struct Message: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    var msgId: String
    /// `sha256(sorted([myNodeId, peerNodeId]).joined())` — stable across both sides.
    var conversationId: String
    var fromNodeId: String
    var toNodeId: String
    /// AES-GCM ciphertext (base64-encoded for SQLite storage).
    var bodyEncrypted: String
    /// Cached plaintext — populated on first successful decrypt, nil on failure.
    var bodyDecrypted: String?
    var timestampMs: Int64
    var deliveryStatus: DeliveryStatus
    var isMine: Bool

    var id: String { msgId }

    var timestamp: Date {
        Date(timeIntervalSince1970: Double(timestampMs) / 1000)
    }

    /// Best-effort display text — falls back to placeholder if not yet decrypted.
    var displayText: String {
        bodyDecrypted ?? "🔒 Encrypted message"
    }
}
