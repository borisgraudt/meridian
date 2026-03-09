import Foundation
import GRDB

struct Conversation: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"

    var conversationId: String
    var peerNodeId: String
    var peerDisplayName: String
    var peerPublicKey: String
    var lastMessageId: String?
    var lastMessagePreview: String?
    var lastActivity: Date
    var unreadCount: Int

    var id: String { conversationId }

    /// Derive a deterministic conversation ID from two node IDs so both sides agree.
    static func makeId(myNodeId: String, peerNodeId: String) -> String {
        let sorted = [myNodeId, peerNodeId].sorted().joined()
        return sorted.sha256Hex
    }

    /// Deterministic avatar colour mirroring `Contact.avatarColor`.
    var avatarColor: String {
        let hash = abs(peerNodeId.hashValue)
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
                      "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
                      "#BB8FCE", "#82E0AA"]
        return colors[hash % colors.count]
    }

    var avatarInitial: String {
        String(peerDisplayName.prefix(1)).uppercased()
    }
}

// MARK: - String SHA-256 helper

import CryptoKit

private extension String {
    var sha256Hex: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
