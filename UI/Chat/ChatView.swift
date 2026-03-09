import SwiftUI

struct ChatView: View {
    @EnvironmentObject var messageStore: MessageStore
    @StateObject private var vm: ChatViewModel

    init(conversation: Conversation) {
        _vm = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            MessageInputBar(
                text: $vm.inputText,
                canSend: vm.canSend,
                isConnected: vm.isConnected,
                onSend: { vm.sendMessage() }
            )
        }
        .navigationTitle(vm.conversation.peerDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AvatarView(
                    initial: vm.conversation.avatarInitial,
                    color: vm.conversation.avatarColor,
                    size: 34
                )
            }
        }
        .task {
            vm.onAppear()
            // Keep polling while the view is on screen — handled globally by
            // MessageStore, but we trigger a load here in case the store isn't
            // yet subscribed.
        }
        .onChange(of: messageStore.messages[vm.conversation.conversationId]?.count) { _, _ in
            vm.scrollToBottom = true
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(vm.messages) { msg in
                        MessageBubble(
                            message: msg,
                            timeString: vm.timeString(for: msg),
                            onCopy: { vm.copy(msg) },
                            onDelete: { vm.delete(msg) }
                        )
                        .id(msg.msgId)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.scrollToBottom) { _, shouldScroll in
                guard shouldScroll, let last = vm.messages.last else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(last.msgId, anchor: .bottom)
                }
                vm.scrollToBottom = false
            }
            .onAppear {
                if let last = vm.messages.last {
                    proxy.scrollTo(last.msgId, anchor: .bottom)
                }
            }
        }
        .background(Color(.systemBackground))
    }
}
