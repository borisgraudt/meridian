import SwiftUI

struct ContactCardView: View {
    let contact: Contact
    let onMessage: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(initial: String(contact.displayName.prefix(1)).uppercased(),
                       color: contact.avatarColor,
                       size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName)
                    .font(.headline)
                Text(contact.shortId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onMessage()
            } label: {
                Image(systemName: "bubble.left.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
