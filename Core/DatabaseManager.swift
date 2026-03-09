import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue!

    func setup() throws {
        let dbURL = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("elysium.sqlite")

        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL mode for better concurrent read performance.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        try migrator.migrate(dbQueue)
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_initial") { db in
            try db.create(table: "contacts", ifNotExists: true) { t in
                t.column("nodeId", .text).primaryKey()
                t.column("displayName", .text).notNull()
                t.column("publicKey", .text).notNull()
                t.column("addedAt", .datetime).notNull()
            }

            try db.create(table: "conversations", ifNotExists: true) { t in
                t.column("conversationId", .text).primaryKey()
                t.column("peerNodeId", .text).notNull()
                t.column("peerDisplayName", .text).notNull()
                t.column("peerPublicKey", .text).notNull()
                t.column("lastMessageId", .text)
                t.column("lastMessagePreview", .text)
                t.column("lastActivity", .datetime).notNull()
                t.column("unreadCount", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "messages", ifNotExists: true) { t in
                t.column("msgId", .text).primaryKey()
                t.column("conversationId", .text).notNull()
                    .references("conversations", onDelete: .cascade)
                t.column("fromNodeId", .text).notNull()
                t.column("toNodeId", .text).notNull()
                t.column("bodyEncrypted", .text).notNull()
                t.column("bodyDecrypted", .text)
                t.column("timestampMs", .integer).notNull()
                t.column("deliveryStatus", .text).notNull().defaults(to: "sending")
                t.column("isMine", .boolean).notNull()
            }

            try db.create(
                index: "idx_messages_conversation",
                on: "messages",
                columns: ["conversationId", "timestampMs"],
                ifNotExists: true
            )
        }

        return m
    }

    // MARK: - Contact CRUD

    func upsertContact(_ contact: Contact) throws {
        try dbQueue.write { try contact.save($0) }
    }

    func allContacts() throws -> [Contact] {
        try dbQueue.read { db in
            try Contact.order(Column("displayName")).fetchAll(db)
        }
    }

    func contact(nodeId: String) throws -> Contact? {
        try dbQueue.read { db in
            try Contact.fetchOne(db, key: nodeId)
        }
    }

    func deleteContact(nodeId: String) throws {
        try dbQueue.write { db in
            try Contact.deleteOne(db, key: nodeId)
        }
    }

    // MARK: - Conversation CRUD

    func upsertConversation(_ conv: Conversation) throws {
        try dbQueue.write { try conv.save($0) }
    }

    func allConversations() throws -> [Conversation] {
        try dbQueue.read { db in
            try Conversation.order(Column("lastActivity").desc).fetchAll(db)
        }
    }

    func conversation(id: String) throws -> Conversation? {
        try dbQueue.read { db in try Conversation.fetchOne(db, key: id) }
    }

    func deleteConversation(id: String) throws {
        try dbQueue.write { db in
            try Conversation.deleteOne(db, key: id)
        }
    }

    // MARK: - Message CRUD

    func insertMessage(_ message: Message) throws {
        try dbQueue.write { try message.insert($0) }
    }

    func messages(conversationId: String, limit: Int = 100) throws -> [Message] {
        try dbQueue.read { db in
            try Message
                .filter(Column("conversationId") == conversationId)
                .order(Column("timestampMs").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func updateDeliveryStatus(msgId: String, status: DeliveryStatus) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET deliveryStatus = ? WHERE msgId = ?",
                arguments: [status.rawValue, msgId]
            )
        }
    }

    func cacheDecryptedBody(msgId: String, plaintext: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET bodyDecrypted = ? WHERE msgId = ?",
                arguments: [plaintext, msgId]
            )
        }
    }

    func updateConversationLastMessage(_ conv: inout Conversation, message: Message) throws {
        conv.lastMessageId = message.msgId
        conv.lastMessagePreview = message.displayText
        conv.lastActivity = message.timestamp
        if !message.isMine { conv.unreadCount += 1 }
        try upsertConversation(conv)
    }

    func markAllRead(conversationId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET deliveryStatus = 'read' WHERE conversationId = ? AND isMine = 0",
                arguments: [conversationId]
            )
            try db.execute(
                sql: "UPDATE conversations SET unreadCount = 0 WHERE conversationId = ?",
                arguments: [conversationId]
            )
        }
    }
}
