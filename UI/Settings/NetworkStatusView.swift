import SwiftUI

struct NetworkStatusView: View {
    @EnvironmentObject var messageStore: MessageStore

    private var peerCount: UInt32 { messageStore.peerCount }

    private var quality: Quality {
        switch peerCount {
        case 0:       return .offline
        case 1:       return .limited
        case 2...4:   return .good
        default:      return .excellent
        }
    }

    enum Quality {
        case excellent, good, limited, offline
        var label: String {
            switch self {
            case .excellent: return "Excellent"
            case .good:      return "Good"
            case .limited:   return "Limited"
            case .offline:   return "Offline"
            }
        }
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good:      return .blue
            case .limited:   return .orange
            case .offline:   return .red
            }
        }
        var icon: String {
            switch self {
            case .excellent: return "wifi"
            case .good:      return "wifi"
            case .limited:   return "wifi.exclamationmark"
            case .offline:   return "wifi.slash"
            }
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: quality.icon)
                        .foregroundStyle(quality.color)
                        .frame(width: 28)
                    VStack(alignment: .leading) {
                        Text(quality.label)
                            .font(.headline)
                        Text("\(peerCount) peer\(peerCount == 1 ? "" : "s") connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Connection Quality")
            }

            Section {
                HStack {
                    Label("Elysium Node", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Text(messageStore.isConnected ? "Running" : "Starting…")
                        .foregroundStyle(messageStore.isConnected ? .green : .secondary)
                        .font(.callout)
                }

                HStack {
                    Label("Protocol", systemImage: "lock.shield")
                    Spacer()
                    Text("TLS + obfs4")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                HStack {
                    Label("NAT Traversal", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text("STUN + Hole Punching")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Network")
            }
        }
        .navigationTitle("Network Status")
        .navigationBarTitleDisplayMode(.inline)
    }
}
