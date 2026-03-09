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
        do {
            try DatabaseManager.shared.setup()
        } catch {
            print("[App] Database setup failed: \(error)")
        }

        // 2. Initialise crypto identity (creates or loads keys from Keychain).
        _ = try? CryptoManager.shared.loadOrCreatePrivateKey()

        // 3. Start embedded Elysium node.
        Task {
            await ElysiumBridge.shared.start()
        }

        // 4. Start message store (polling loop).
        MessageStore.shared.start()
        ContactsManager.shared.loadAll()

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
                await MessageStore.shared.sendMessage(
                    conversationId: "", peerNodeId: "", text: ""
                )
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
