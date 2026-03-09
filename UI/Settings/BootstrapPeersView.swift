import SwiftUI

struct BootstrapPeersView: View {
    @AppStorage("bootstrapPeers") private var storedPeers = ""
    @AppStorage("listenPort") private var listenPort = 0
    @State private var newPeer = ""
    @State private var portText = ""

    private var peers: [String] {
        storedPeers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Listen Port")
                    Spacer()
                    TextField("4001", text: $portText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: portText) { _, val in
                            listenPort = Int(val) ?? 0
                        }
                }
            } header: {
                Text("This Device")
            } footer: {
                Text("Set a fixed port (e.g. 4001) so others can connect to you as a bootstrap node. Leave blank for automatic. Takes effect on next launch.")
            }

            Section {
                ForEach(peers, id: \.self) { peer in
                    Text(peer)
                        .font(.system(.body, design: .monospaced))
                }
                .onDelete(perform: deletePeers)
            } header: {
                Text("Configured Peers")
            } footer: {
                Text("Changes take effect on next app launch.")
            }

            Section {
                HStack {
                    TextField("192.168.1.100:4001", text: $newPeer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("Add") {
                        addPeer()
                    }
                    .disabled(newPeer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Add Peer")
            } footer: {
                Text("Format: ip:port or hostname:port  Example: node.example.com:4001")
            }
        }
        .navigationTitle("Bootstrap Peers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear {
            portText = listenPort > 0 ? "\(listenPort)" : ""
        }
        .overlay {
            if peers.isEmpty {
                ContentUnavailableView(
                    "No Bootstrap Peers",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Add at least one peer to connect to the Elysium network over the internet.")
                )
            }
        }
    }

    private func addPeer() {
        let trimmed = newPeer.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !peers.contains(trimmed) else { return }
        var updated = peers
        updated.append(trimmed)
        storedPeers = updated.joined(separator: ",")
        newPeer = ""
    }

    private func deletePeers(at offsets: IndexSet) {
        var updated = peers
        updated.remove(atOffsets: offsets)
        storedPeers = updated.joined(separator: ",")
    }
}
