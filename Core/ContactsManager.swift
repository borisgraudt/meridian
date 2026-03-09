import Foundation
final class ContactsManager: ObservableObject {
    static let shared = ContactsManager()

    @Published private(set) var contacts: [Contact] = []

    func loadAll() {
        contacts = (try? DatabaseManager.shared.allContacts()) ?? []
    }

    // MARK: - Add contact

    /// Add a contact by node ID.  Attempts to resolve their public key from the mesh.
    /// - Parameter displayName: User-visible name (stored locally only).
    /// - Parameter publicKeyBase64: Supply directly if already known (e.g. from QR).
    @discardableResult
    func addContact(
        nodeId: String,
        displayName: String,
        publicKeyBase64: String? = nil
    ) async throws -> Contact {
        // If no public key supplied, try to fetch from mesh.
        let pubKey: String
        if let supplied = publicKeyBase64 {
            pubKey = supplied
        } else {
            // ElysiumBridge.shared.resolveNodeId resolves name → node_id;
            // the public key should be embedded in the DHT record.
            // INTEGRATION: replace with actual DHT public-key lookup.
            pubKey = ""
        }

        let contact = Contact(
            nodeId: nodeId,
            displayName: displayName,
            publicKey: pubKey,
            addedAt: Date()
        )
        try DatabaseManager.shared.upsertContact(contact)

        // Also create/refresh the conversation record.
        let myNodeId = await ElysiumBridge.shared.nodeId ?? ""
        let convId = Conversation.makeId(myNodeId: myNodeId, peerNodeId: nodeId)
        var conv = Conversation(
            conversationId: convId,
            peerNodeId: nodeId,
            peerDisplayName: displayName,
            peerPublicKey: pubKey,
            lastMessageId: nil,
            lastMessagePreview: nil,
            lastActivity: Date(),
            unreadCount: 0
        )
        if let existing = try? DatabaseManager.shared.conversation(id: convId) {
            conv = existing
            conv.peerDisplayName = displayName
            if !pubKey.isEmpty { conv.peerPublicKey = pubKey }
        }
        try DatabaseManager.shared.upsertConversation(conv)

        await MainActor.run { loadAll() }
        return contact
    }

    // MARK: - Remove

    func removeContact(nodeId: String) throws {
        try DatabaseManager.shared.deleteContact(nodeId: nodeId)
        loadAll()
    }

    // MARK: - Lookup

    func contact(for nodeId: String) -> Contact? {
        contacts.first { $0.nodeId == nodeId }
    }
}
