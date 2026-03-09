import Foundation
import Combine

final class ConversationListViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var showNewChat = false

    private let store = MessageStore.shared
    private var cancellables = Set<AnyCancellable>()

    var conversations: [Conversation] {
        let all = store.conversations
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.peerDisplayName.lowercased().contains(q) ||
            $0.peerNodeId.lowercased().contains(q) ||
            ($0.lastMessagePreview?.lowercased().contains(q) ?? false)
        }
    }

    var isConnected: Bool { store.isConnected }
    var peerCount: UInt32 { store.peerCount }

    // MARK: - Actions

    func deleteConversation(_ conv: Conversation) {
        try? DatabaseManager.shared.deleteConversation(id: conv.conversationId)
    }

    func relativeTimestamp(for conv: Conversation) -> String {
        let interval = Date().timeIntervalSince(conv.lastActivity)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: conv.lastActivity)
    }
}
