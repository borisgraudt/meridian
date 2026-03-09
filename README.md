# Meridian

A decentralized, end-to-end encrypted messenger for iOS built on the Elysium P2P protocol. No servers, no phone number, no central authority.

## Architecture

```
Meridian/
├── Core/
│   ├── ElysiumBridge.swift      # Swift actor wrapping the Elysium C FFI
│   ├── CryptoManager.swift      # CryptoKit Curve25519 E2E encryption (Keychain-backed)
│   ├── MessageStore.swift       # ObservableObject — polling loop, inbox, send
│   ├── ContactsManager.swift    # Contact CRUD
│   └── DatabaseManager.swift   # GRDB SQLite — messages, conversations, contacts
├── Models/
│   ├── Message.swift
│   ├── Conversation.swift
│   ├── Contact.swift
│   └── DeliveryStatus.swift
├── UI/
│   ├── Onboarding/              # Identity generation, QR display
│   ├── ConversationList/        # Chat list
│   ├── Chat/                    # ChatView + ChatViewModel
│   ├── Contacts/                # Add/view contacts
│   └── Settings/                # Network status, bootstrap peers, profile
├── ElysiumCore.xcframework      # Pre-built Elysium node (iOS arm64 + Simulator)
└── Resources/
    └── Info.plist
```

## Two key systems

| Key | Purpose | Storage |
|-----|---------|---------|
| Elysium transport key | Node identity & routing on the P2P network | `data_dir` on disk (managed by the C library) |
| CryptoKit Curve25519 | End-to-end message encryption | Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) |

QR codes and contact public keys use the **CryptoKit key**, not the Elysium transport key.

## Connecting to the network

The node discovers peers via:
1. **Bonjour** (`_elysium._tcp`) — automatic on the same WiFi, no config needed
2. **Bootstrap peers** — required to connect over the internet

To configure bootstrap peers: **Settings → Bootstrap Peers → Add Peer** (`ip:port`).

### Using the iOS Simulator as a local bootstrap node

1. Run the app in the iOS Simulator on your Mac
2. In Simulator: **Settings → Bootstrap Peers → This Device → Listen Port** — set `4001`
3. Restart the simulator app
4. Get your Mac's local IP: `ipconfig getifaddr en0`
5. On the real device: add `<mac-ip>:4001` as a bootstrap peer and restart

> Simulator and real device must be on the same WiFi network.

## Requirements

- Xcode 16+
- iOS 17+
- Swift 5.9+
