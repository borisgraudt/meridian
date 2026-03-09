import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var contactsManager: ContactsManager
    @StateObject private var vm = ConversationListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.conversations.isEmpty && vm.searchText.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Elysium")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    connectionBadge
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.showNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .searchable(text: $vm.searchText, prompt: "Search conversations")
            .sheet(isPresented: $vm.showNewChat) {
                AddContactView()
                    .environmentObject(contactsManager)
            }
        }
    }

    // MARK: - Connection badge

    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(vm.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            if vm.peerCount > 0 {
                Text("\(vm.peerCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Conversation list

    private var conversationList: some View {
        List {
            ForEach(vm.conversations) { conv in
                NavigationLink {
                    ChatView(conversation: conv)
                        .environmentObject(messageStore)
                } label: {
                    ConversationRow(conv: conv, vm: vm)
                }
                .listRowBackground(Color(.systemGray6))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        vm.deleteConversation(conv)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            // Manual pull-to-refresh triggers an immediate inbox poll.
            let _ = await ElysiumBridge.shared.pollInbox()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No conversations yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Add a contact") { vm.showNewChat = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

// MARK: - Conversation row

private struct ConversationRow: View {
    let conv: Conversation
    let vm: ConversationListViewModel

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initial: conv.avatarInitial, color: conv.avatarColor, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conv.peerDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(vm.relativeTimestamp(for: conv))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(conv.lastMessagePreview ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if conv.unreadCount > 0 {
                        Text("\(conv.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Shared avatar view

struct AvatarView: View {
    let initial: String
    let color: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: color) ?? .blue)
                .frame(width: size, height: size)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Hex color helper

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}
