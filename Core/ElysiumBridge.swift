import Foundation

// MARK: - Message received via FFI callback

struct InboundWireMessage: Decodable {
    let msgId: String
    let from: String
    let to: String
    let timestampMs: Int64
    let payloadEncrypted: String // base64
    let deliveryStatus: String

    enum CodingKeys: String, CodingKey {
        case msgId = "msg_id"
        case from, to
        case timestampMs = "timestamp_ms"
        case payloadEncrypted = "payload_encrypted"
        case deliveryStatus = "delivery_status"
    }
}

// MARK: - Actor

actor ElysiumBridge {
    static let shared = ElysiumBridge()

    private var handle: OpaquePointer?

    // Queued messages received via FFI callback before an async consumer picks them up.
    private var pendingMessages: [InboundWireMessage] = []

    // MARK: Lifecycle

    /// Start the embedded Elysium node.  Call once on app launch.
    func start(port: UInt16 = 0, configJSON: String = "{}") {
        guard handle == nil else {
            print("[ElysiumBridge] start() called but node already running, id=\(nodeId ?? "?")")
            return
        }
        print("[ElysiumBridge] calling elysium_start(port:\(port), config:\(configJSON))")
        handle = configJSON.withCString { cfg in
            elysium_start(port, cfg)
        }
        guard handle != nil else {
            print("[ElysiumBridge] ❌ elysium_start returned nil — node failed to start")
            return
        }
        print("[ElysiumBridge] ✅ node started — id=\(nodeId ?? "<nil>")  pubkey=\(publicKeyBase64 ?? "<nil>")")
    }

    /// Stop the node.  Called when the app terminates.
    func stop() {
        guard let h = handle else {
            print("[ElysiumBridge] stop() called but node not running")
            return
        }
        print("[ElysiumBridge] stopping node...")
        elysium_stop(h)
        handle = nil
        print("[ElysiumBridge] node stopped")
    }

    // MARK: Identity

    var nodeId: String? {
        guard let h = handle, let ptr = elysium_get_node_id(h) else { return nil }
        return String(cString: ptr)
    }

    var publicKeyBase64: String? {
        guard let h = handle, let ptr = elysium_get_public_key(h) else { return nil }
        return String(cString: ptr)
    }

    // MARK: Messaging

    /// Encrypt `plaintext` for `recipient` and hand it to the Elysium transport layer.
    func sendMessage(to recipientNodeId: String, encryptedPayload: Data) async -> Bool {
        guard let h = handle else {
            print("[ElysiumBridge] ❌ sendMessage — node not running")
            return false
        }
        print("[ElysiumBridge] → sendMessage to=\(recipientNodeId.prefix(16))... bytes=\(encryptedPayload.count)")
        let result = encryptedPayload.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return recipientNodeId.withCString { rid in
                elysium_send_message(h, rid, ptr, UInt(encryptedPayload.count))
            }
        }
        print("[ElysiumBridge] → sendMessage result=\(result ? "✅ ok" : "❌ failed")")
        return result
    }

    /// Drain the node's inbox and return all pending messages.
    func pollInbox() -> [InboundWireMessage] {
        guard let h = handle else {
            print("[ElysiumBridge] pollInbox — node not running, skipping")
            return []
        }

        var rawCount = 0
        elysium_poll_inbox(h, { jsonPtr in
            guard let jsonPtr else { return }
            let json = String(cString: jsonPtr)
            print("[ElysiumBridge] ← raw inbox message: \(json.prefix(200))")
            if let data = json.data(using: .utf8),
               let msg = try? JSONDecoder().decode(InboundWireMessage.self, from: data) {
                ElysiumBridge._callbackQueue.async {
                    ElysiumBridge._pendingCallbackMessages.append(msg)
                }
            } else {
                print("[ElysiumBridge] ← ❌ failed to decode inbox JSON: \(json.prefix(200))")
            }
        })

        let messages = ElysiumBridge.drainCallbackMessages()
        if !messages.isEmpty {
            print("[ElysiumBridge] ← drained \(messages.count) message(s) from inbox")
        }
        return messages
    }

    // MARK: Connection status

    var peerCount: UInt32 {
        guard let h = handle else { return 0 }
        return elysium_peer_count(h)
    }

    var isConnected: Bool {
        guard let h = handle else { return false }
        return elysium_is_connected(h)
    }

    // MARK: Name resolution

    /// Resolve a human-readable name to a node_id via the DHT.  Returns nil if not found.
    func resolveNodeId(for name: String) async -> String? {
        guard let h = handle else { return nil }
        let result = name.withCString { elysium_resolve_name(h, $0) }
        guard let result else { return nil }
        return String(cString: result)
    }

    // MARK: Bundles

    func exportBundle(to path: String) async -> Bool {
        guard let h = handle else { return false }
        return path.withCString { elysium_export_bundle(h, $0) }
    }

    func importBundle(from path: String) async -> Bool {
        guard let h = handle else { return false }
        return path.withCString { elysium_import_bundle(h, $0) }
    }
}

// MARK: - Callback bridging helpers (file-scope, not actor-isolated)

// The C callback runs on an arbitrary thread; we bridge via a serial queue.
extension ElysiumBridge {
    fileprivate static let _callbackQueue = DispatchQueue(label: "com.elysium.ffi.callback")
    fileprivate static var _pendingCallbackMessages: [InboundWireMessage] = []

    fileprivate static func drainCallbackMessages() -> [InboundWireMessage] {
        var result: [InboundWireMessage] = []
        _callbackQueue.sync {
            result = _pendingCallbackMessages
            _pendingCallbackMessages = []
        }
        return result
    }
}
