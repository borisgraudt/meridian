import SwiftUI
import PushKit
import BackgroundTasks

@main
struct ElysiumMessengerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var messageStore = MessageStore.shared
    @StateObject private var contactsManager = ContactsManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("displayName") private var displayName = ""

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentRootView()
                        .environmentObject(messageStore)
                        .environmentObject(contactsManager)
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environmentObject(messageStore)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - App Delegate (VoIP + Background Tasks)

final class AppDelegate: NSObject, UIApplicationDelegate, PKPushRegistryDelegate {

    private var voipRegistry: PKPushRegistry?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. Set up SQLite.
        print("[App] ── launch ──────────────────────────")
        do {
            try DatabaseManager.shared.setup()
            print("[App] ✅ database ready")
        } catch {
            print("[App] ❌ database setup failed: \(error)")
        }

        // 2. Initialise crypto identity (creates or loads keys from Keychain).
        do {
            _ = try CryptoManager.shared.loadOrCreatePrivateKey()
            let pubKey = (try? CryptoManager.shared.publicKeyBase64) ?? "<error>"
            print("[App] ✅ crypto identity ready — pubKey=\(pubKey.prefix(20))...")
        } catch {
            print("[App] ❌ crypto identity failed: \(error)")
        }

        // 3. Start embedded Elysium node.
        print("[App] starting Elysium node...")
        Task {
            let docsDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0].path

            var configDict: [String: Any] = ["data_dir": docsDir]
            let peersString = UserDefaults.standard.string(forKey: "bootstrapPeers") ?? ""
            let peersArray = peersString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !peersArray.isEmpty {
                configDict["bootstrap_peers"] = peersArray
            }
            let config = (try? JSONSerialization.data(withJSONObject: configDict))
                .flatMap { String(data: $0, encoding: .utf8) }
                ?? "{\"data_dir\":\"\(docsDir)\"}"

            let storedPort = UserDefaults.standard.integer(forKey: "listenPort")
            let listenPort = UInt16(storedPort > 0 ? storedPort : 0)
            print("[App] elysium config: \(config), port: \(listenPort)")
            await ElysiumBridge.shared.start(port: listenPort, configJSON: config)
        }

        // 4. Start message store (polling loop).
        MessageStore.shared.start()
        ContactsManager.shared.loadAll()
        print("[App] ✅ MessageStore + ContactsManager started")

        // 5. Register for VoIP push so iOS keeps our socket alive in background.
        voipRegistry = PKPushRegistry(queue: .main)
        voipRegistry?.delegate = self
        voipRegistry?.desiredPushTypes = [.voIP]

        // 6. Register background inbox-poll task (fallback when socket drops).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.borisgraudt.elysium.inbox-poll",
            using: nil
        ) { task in
            Task {
                let _ = await ElysiumBridge.shared.pollInbox()
                task.setTaskCompleted(success: true)
            }
        }

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Task { await ElysiumBridge.shared.stop() }
        MessageStore.shared.stop()
    }

    // MARK: PKPushRegistryDelegate

    func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        // INTEGRATION: send VoIP push token to a notification server if one is used.
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        Task {
            // Wake up and drain inbox on a push nudge.
            let inbound = await ElysiumBridge.shared.pollInbox()
            _ = inbound
            completion()
        }
    }
}

// MARK: - Content root (tab bar)

struct ContentRootView: View {
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var contactsManager: ContactsManager

    var body: some View {
        TabView {
            ConversationListView()
                .tabItem {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right")
                }
                .badge(totalUnread)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .accentColor(.blue)
    }

    private var totalUnread: Int {
        messageStore.conversations.reduce(0) { $0 + $1.unreadCount }
    }
}
