import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var contactsManager: ContactsManager

    @State private var onionModeEnabled = false
    @State private var showExportAlert = false
    @State private var exportPath: String? = nil

    var body: some View {
        NavigationStack {
            List {
                // Profile
                Section {
                    NavigationLink { ProfileView() } label: {
                        Label("Profile & QR Code", systemImage: "qrcode")
                    }
                }

                // Network
                Section("Network") {
                    NavigationLink {
                        NetworkStatusView()
                            .environmentObject(messageStore)
                    } label: {
                        HStack {
                            Label("Network Status", systemImage: "wifi")
                            Spacer()
                            connectionDot
                        }
                    }

                    Toggle(isOn: $onionModeEnabled) {
                        Label("Onion Routing (3 hops)", systemImage: "eyes.inverse")
                    }
                    .onChange(of: onionModeEnabled) { _, enabled in
                        // INTEGRATION: call elysium_set_onion_mode FFI
                        print("[Settings] Onion mode: \(enabled)")
                    }
                }

                // Contacts
                Section("Contacts (\(contactsManager.contacts.count))") {
                    NavigationLink {
                        contactsList
                    } label: {
                        Label("Manage Contacts", systemImage: "person.2")
                    }
                }

                // Data
                Section("Data") {
                    Button {
                        Task { await exportBundle() }
                    } label: {
                        Label("Export Bundle (offline sync)", systemImage: "square.and.arrow.up")
                    }
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Protocol")
                        Spacer()
                        Text("Elysium v1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var connectionDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(messageStore.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(messageStore.isConnected ? "\(messageStore.peerCount) peers" : "Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var contactsList: some View {
        List {
            ForEach(contactsManager.contacts) { contact in
                ContactCardView(
                    contact: contact,
                    onMessage: {
                        // Navigate to chat — handled via ConversationListView
                    },
                    onDelete: {
                        try? contactsManager.removeContact(nodeId: contact.nodeId)
                    }
                )
            }
        }
        .navigationTitle("Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if contactsManager.contacts.isEmpty {
                ContentUnavailableView(
                    "No Contacts",
                    systemImage: "person.slash",
                    description: Text("Add contacts by tapping the compose button in Chats.")
                )
            }
        }
    }

    private func exportBundle() async {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("elysium-bundle.zip").path
        let success = await ElysiumBridge.shared.exportBundle(to: path)
        if success {
            exportPath = path
            showExportAlert = true
        }
    }
}
