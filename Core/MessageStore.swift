import Foundation
import Combine

final class MessageStore: ObservableObject {
    static let shared = MessageStore()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messages: [String: [Message]] = [:] // keyed by conversationId

    /// Current peer count — drives NetworkStatusView.
    @Published private(set) var peerCount: UInt32 = 0
    @Published private(set) var isConnected: Bool = false

    private var pollingTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
        loadFromDatabase()
        startPolling()
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Send

    /// Encrypt `text` for the peer, persist optimistically, hand off to the transport.
    @discardableResult
    func sendMessage(conversationId: String, peerNodeId: String, text: String) async -> Message? {
        guard let conv = try? DatabaseManager.shared.conversation(id: conversationId),
              let myNodeId = await ElysiumBridge.shared.nodeId else { return nil }

        let encryptedData: Data
        do {
            encryptedData = try CryptoManager.shared.encrypt(text, recipientPublicKeyBase64: conv.peerPublicKey)
        } catch {
            print("[MessageStore] Encryption failed: \(error)")
            return nil
        }

        var msg = Message(
            msgId: UUID().uuidString,
            conversationId: conversationId,
            fromNodeId: myNodeId,
            toNodeId: peerNodeId,
            bodyEncrypted: encryptedData.base64EncodedString(),
            bodyDecrypted: text,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            deliveryStatus: .sending,
            isMine: true
        )

        try? DatabaseManager.shared.insertMessage(msg)
        appendToCache(msg)

        // Retry up to 5 times with 600 ms intervals.
        var success = false
        for _ in 0..<5 {
            success = await ElysiumBridge.shared.sendMessage(to: peerNodeId, encryptedPayload: encryptedData)
            if success { break }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        msg.deliveryStatus = success ? .sent : .failed
        try? DatabaseManager.shared.updateDeliveryStatus(msgId: msg.msgId, status: msg.deliveryStatus)
        updateCacheStatus(msgId: msg.msgId, conversationId: conversationId, status: msg.deliveryStatus)

        // Update conversation preview.
        if var c = try? DatabaseManager.shared.conversation(id: conversationId) {
            try? DatabaseManager.shared.updateConversationLastMessage(&c, message: msg)
            await MainActor.run { refreshConversations() }
        }

        return msg
    }

    // MARK: - Load messages for a conversation

    func loadMessages(conversationId: String) {
        let fetched = (try? DatabaseManager.shared.messages(conversationId: conversationId)) ?? []
        DispatchQueue.main.async {
            self.messages[conversationId] = fetched
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func poll() async {
        // Update connectivity stats.
        let count = await ElysiumBridge.shared.peerCount
        let connected = await ElysiumBridge.shared.isConnected
        await MainActor.run {
            peerCount = count
            isConnected = connected
        }

        // Drain inbox.
        let inbound = await ElysiumBridge.shared.pollInbox()
        guard !inbound.isEmpty else { return }

        let myNodeId = await ElysiumBridge.shared.nodeId ?? ""

        for wire in inbound {
            await handleInbound(wire, myNodeId: myNodeId)
        }
    }

    private func handleInbound(_ wire: InboundWireMessage, myNodeId: String) async {
        let convId = Conversation.makeId(myNodeId: myNodeId, peerNodeId: wire.from)

        // Resolve sender public key for decryption.
        let senderPublicKey: String
        if let contact = try? DatabaseManager.shared.contact(nodeId: wire.from) {
            senderPublicKey = contact.publicKey
        } else {
            // Unknown sender — queue message with no decryption.
            senderPublicKey = ""
        }

        let encryptedData = Data(base64Encoded: wire.payloadEncrypted) ?? Data()

        var decrypted: String? = nil
        if !senderPublicKey.isEmpty {
            decrypted = try? CryptoManager.shared.decrypt(encryptedData, senderPublicKeyBase64: senderPublicKey)
        }

        // Duplicate guard.
        guard !(messages[convId]?.contains(where: { $0.msgId == wire.msgId }) ?? false) else { return }

        let msg = Message(
            msgId: wire.msgId,
            conversationId: convId,
            fromNodeId: wire.from,
            toNodeId: wire.to,
            bodyEncrypted: wire.payloadEncrypted,
            bodyDecrypted: decrypted,
            timestampMs: wire.timestampMs,
            deliveryStatus: .delivered,
            isMine: false
        )

        try? DatabaseManager.shared.insertMessage(msg)
        if let plaintext = decrypted {
            try? DatabaseManager.shared.cacheDecryptedBody(msgId: msg.msgId, plaintext: plaintext)
        }

        appendToCache(msg)

        // Upsert conversation.
        var conv: Conversation
        if let existing = try? DatabaseManager.shared.conversation(id: convId) {
            conv = existing
        } else {
            let displayName = ContactsManager.shared.contact(for: wire.from)?.displayName ?? wire.from
            let pubKey = ContactsManager.shared.contact(for: wire.from)?.publicKey ?? ""
            conv = Conversation(
                conversationId: convId,
                peerNodeId: wire.from,
                peerDisplayName: displayName,
                peerPublicKey: pubKey,
                lastMessageId: nil,
                lastMessagePreview: nil,
                lastActivity: Date(),
                unreadCount: 0
            )
        }
        try? DatabaseManager.shared.updateConversationLastMessage(&conv, message: msg)
        await MainActor.run { refreshConversations() }
    }

    // MARK: - Mark read

    func markRead(conversationId: String) {
        try? DatabaseManager.shared.markAllRead(conversationId: conversationId)
        if let idx = conversations.firstIndex(where: { $0.conversationId == conversationId }) {
            conversations[idx].unreadCount = 0
        }
    }

    // MARK: - Helpers

    private func loadFromDatabase() {
        conversations = (try? DatabaseManager.shared.allConversations()) ?? []
    }

    private func refreshConversations() {
        conversations = (try? DatabaseManager.shared.allConversations()) ?? []
    }

    @MainActor
    private func appendToCache(_ msg: Message) {
        var list = messages[msg.conversationId] ?? []
        list.append(msg)
        messages[msg.conversationId] = list
    }

    @MainActor
    private func updateCacheStatus(msgId: String, conversationId: String, status: DeliveryStatus) {
        guard var list = messages[conversationId],
              let idx = list.firstIndex(where: { $0.msgId == msgId }) else { return }
        list[idx].deliveryStatus = status
        messages[conversationId] = list
    }
}
