import SwiftUI

struct MessageInputBar: View {
    @Binding var text: String
    let canSend: Bool
    let isConnected: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit {
                    if canSend { send() }
                }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            if !isConnected {
                Text("Offline — messages will be delivered when connected")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
    }

    private func send() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onSend()
    }
}
