import SwiftUI

struct MessageBubble: View {
    let message: Message
    let timeString: String
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var isMe: Bool { message.isMine }

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                Text(message.displayText)
                    .font(.body)
                    .foregroundStyle(isMe ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isMe ? Color.blue : Color(.systemGray5))
                    .clipShape(BubbleShape(isMe: isMe))

                HStack(spacing: 4) {
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if isMe {
                        deliveryIcon
                    }
                }
                .padding(.horizontal, 4)
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.85, anchor: isMe ? .bottomTrailing : .bottomLeading)
                    .combined(with: .opacity),
                removal: .opacity
            ))

            if !isMe { Spacer(minLength: 60) }
        }
        .contextMenu {
            Button { onCopy() } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var deliveryIcon: some View {
        let status = message.deliveryStatus
        Image(systemName: status.icon)
            .font(.caption2)
            .foregroundStyle(status.isRead ? .blue : .secondary)
    }
}

// MARK: - Bubble tail shape

private struct BubbleShape: Shape {
    let isMe: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = 6
        var path = Path()

        if isMe {
            path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY,
                                           width: rect.width - tail, height: rect.height),
                                cornerSize: CGSize(width: r, height: r))
            path.move(to: CGPoint(x: rect.maxX - tail, y: rect.maxY - 20))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 8))
            path.addLine(to: CGPoint(x: rect.maxX - tail, y: rect.maxY - 8))
        } else {
            path.addRoundedRect(in: CGRect(x: rect.minX + tail, y: rect.minY,
                                           width: rect.width - tail, height: rect.height),
                                cornerSize: CGSize(width: r, height: r))
            path.move(to: CGPoint(x: rect.minX + tail, y: rect.maxY - 20))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 8))
            path.addLine(to: CGPoint(x: rect.minX + tail, y: rect.maxY - 8))
        }
        return path
    }
}
