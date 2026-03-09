import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct ProfileView: View {
    @AppStorage("displayName") private var displayName: String = ""
    @State private var nodeId: String = ""
    @State private var publicKey: String = ""
    @State private var editingName: String = ""
    @State private var isEditingName = false
    @State private var copied = false

    var body: some View {
        List {
            // QR code section
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 14) {
                        QRCodeView(content: qrPayload)
                            .frame(width: 200, height: 200)
                            .padding(12)
                            .background(.white)
                            .cornerRadius(16)

                        Text(displayName.isEmpty ? "Anonymous" : displayName)
                            .font(.title3.bold())
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // Identity section
            Section("Your Node ID") {
                HStack {
                    Text(nodeId.isEmpty ? "Loading…" : nodeId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = nodeId
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? .green : .blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Display name edit
            Section("Display Name") {
                if isEditingName {
                    HStack {
                        TextField("Name", text: $editingName)
                            .autocorrectionDisabled()
                        Button("Save") {
                            displayName = editingName
                            isEditingName = false
                        }
                        .foregroundStyle(.blue)
                    }
                } else {
                    HStack {
                        Text(displayName.isEmpty ? "Not set" : displayName)
                            .foregroundStyle(displayName.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Edit") {
                            editingName = displayName
                            isEditingName = true
                        }
                        .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            nodeId = await ElysiumBridge.shared.nodeId ?? ""
            publicKey = await ElysiumBridge.shared.publicKeyBase64 ?? ""
        }
    }

    /// elysium://<nodeId>?name=<displayName>&pk=<publicKey>
    private var qrPayload: String {
        var components = URLComponents()
        components.scheme = "elysium"
        components.host = nodeId
        var items: [URLQueryItem] = []
        if !displayName.isEmpty { items.append(URLQueryItem(name: "name", value: displayName)) }
        if !publicKey.isEmpty  { items.append(URLQueryItem(name: "pk", value: publicKey)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? nodeId
    }
}
