import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var messageStore: MessageStore

    @State private var step: Step = .welcome
    @State private var displayName: String = ""
    @State private var nodeId: String = ""
    @State private var publicKeyBase64: String = ""
    @State private var isGenerating = false
    @State private var showAddContact = false

    enum Step { case welcome, generating, name, qr, done }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch step {
            case .welcome:     welcomeScreen
            case .generating:  generatingScreen
            case .name:        nameScreen
            case .qr:          qrScreen
            case .done:        doneScreen
            }
        }
        .animation(.easeInOut(duration: 0.35), value: step)
    }

    // MARK: - Screens

    private var welcomeScreen: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "network")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Elysium Messenger")
                    .font(.largeTitle.bold())

                Text("No servers.\nNo phone number.\nCensorship-resistant.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            primaryButton("Get Started") {
                step = .generating
                Task { await generateIdentity() }
            }
        }
        .padding(32)
    }

    private var generatingScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(2)
                .tint(.blue)
            Text("Generating your identity…")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 32)
            Spacer()
        }
    }

    private var nameScreen: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Choose a display name")
                .font(.title2.bold())

            Text("This name is stored locally only — it is never broadcast to the network.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            Spacer()

            primaryButton("Continue", disabled: displayName.trimmingCharacters(in: .whitespaces).isEmpty) {
                UserDefaults.standard.set(displayName, forKey: "displayName")
                step = .qr
            }
        }
        .padding(32)
    }

    private var qrScreen: some View {
        VStack(spacing: 24) {
            Text("Your Elysium Address")
                .font(.title2.bold())

            Text("Share this QR code so others can add you.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            QRCodeView(content: nodeId)
                .frame(width: 220, height: 220)
                .padding(16)
                .background(.white)
                .cornerRadius(16)

            Text(nodeId)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Button("Copy ID") {
                UIPasteboard.general.string = nodeId
            }
            .foregroundStyle(.blue)

            Spacer()

            primaryButton("Continue") { step = .done }
        }
        .padding(32)
    }

    private var doneScreen: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("You're ready.")
                .font(.largeTitle.bold())

            Text("Add contacts via their node ID or QR code to start messaging.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            primaryButton("Start Messaging") {
                hasCompletedOnboarding = true
            }
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func generateIdentity() async {
        isGenerating = true
        await ElysiumBridge.shared.start()
        // Give the node a moment to initialise.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        nodeId = await ElysiumBridge.shared.nodeId ?? ""
        publicKeyBase64 = await ElysiumBridge.shared.publicKeyBase64 ?? ""
        isGenerating = false
        step = .name
    }

    @ViewBuilder
    private func primaryButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(disabled ? Color.gray : Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(14)
        }
        .disabled(disabled)
    }
}

// MARK: - QR Code generator (CoreImage)

struct QRCodeView: View {
    let content: String

    var body: some View {
        if let image = generateQR() {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
        }
    }

    private func generateQR() -> UIImage? {
        guard let data = content.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return UIImage(ciImage: scaled)
    }
}
