import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var scrollToBottom: Bool = false

    let conversation: Conversation
    private let store = MessageStore.shared

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    var messages: [Message] {
        store.messages[conversation.conversationId] ?? []
    }

    var isConnected: Bool { store.isConnected }
    var canSend: Bool { !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isSending }

    // MARK: - Load

    func onAppear() {
        store.loadMessages(conversationId: conversation.conversationId)
        store.markRead(conversationId: conversation.conversationId)
    }

    // MARK: - Send

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        isSending = true

        Task {
            await store.sendMessage(
                conversationId: conversation.conversationId,
                peerNodeId: conversation.peerNodeId,
                text: text
            )
            isSending = false
            scrollToBottom = true
        }
    }

    // MARK: - Context menu actions

    func copy(_ message: Message) {
        UIPasteboard.general.string = message.displayText
    }

    func delete(_ message: Message) {
        // Optimistic removal from cache; SQLite row remains for audit.
        if var list = store.messages[conversation.conversationId],
           let idx = list.firstIndex(where: { $0.msgId == message.msgId }) {
            list.remove(at: idx)
            store.messages[conversation.conversationId] = list
        }
    }

    // MARK: - Relative time

    func timeString(for message: Message) -> String {
        let formatter = DateFormatter()
        let age = Date().timeIntervalSince(message.timestamp)
        if age < 86400 {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MMM d, HH:mm"
        }
        return formatter.string(from: message.timestamp)
    }
}
