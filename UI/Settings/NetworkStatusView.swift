import SwiftUI
import Darwin

struct NetworkStatusView: View {
    @EnvironmentObject var messageStore: MessageStore

    @State private var nodeId: String? = nil
    @State private var localIP: String? = nil

    private var peerCount: UInt32 { messageStore.peerCount }
    private var listenPort: Int {
        UserDefaults.standard.integer(forKey: "listenPort")
    }

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
                if let ip = localIP {
                    let portLabel = listenPort > 0 ? "\(listenPort)" : "auto"
                    let address = listenPort > 0 ? "\(ip):\(listenPort)" : nil
                    HStack {
                        Label("\(ip):\(portLabel)", systemImage: "network")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if let address {
                            Button {
                                UIPasteboard.general.string = address
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Label("IP not found", systemImage: "network.slash")
                        .foregroundStyle(.secondary)
                }
                if let id = nodeId {
                    HStack {
                        Label(String(id.prefix(24)) + "…", systemImage: "key.horizontal")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = id
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("This Node (use as bootstrap peer)")
            } footer: {
                Text("To use as a bootstrap node: set a fixed Listen Port in Bootstrap Peers settings, then use this address.")
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
        .task {
            nodeId = await ElysiumBridge.shared.nodeId
            localIP = Self.localIPAddress()
        }
    }

    // MARK: - Helpers

    private static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }
        var ptr = first
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback, ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if ip.hasPrefix("192.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                        address = ip
                        break
                    }
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return address
    }
}
