import SwiftUI
import AVFoundation

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var contactsManager: ContactsManager

    @State private var selectedTab: Tab = .enterID
    @State private var nodeId: String = ""
    @State private var displayName: String = ""
    @State private var publicKey: String = ""
    @State private var isAdding = false
    @State private var statusMessage: String? = nil
    @State private var addedSuccessfully = false

    enum Tab: String, CaseIterable {
        case enterID = "Enter ID"
        case scanQR = "Scan QR"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .enterID: enterIDView
                case .scanQR:  qrScannerView
                }

                Spacer()
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if selectedTab == .enterID {
                        Button("Add") { addContact() }
                            .disabled(nodeId.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                    }
                }
            }
            .alert("Contact Added", isPresented: $addedSuccessfully) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(displayName.isEmpty ? "Contact" : displayName) has been added.")
            }
        }
    }

    // MARK: - Enter ID tab

    private var enterIDView: some View {
        Form {
            Section("Node ID") {
                TextField("Paste node ID here", text: $nodeId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Display Name") {
                TextField("Name (optional)", text: $displayName)
                    .autocorrectionDisabled()
            }

            Section("Public Key (optional)") {
                TextField("Base64 Curve25519 public key", text: $publicKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
            }

            if let status = statusMessage {
                Section {
                    Text(status)
                        .foregroundStyle(isAdding ? .secondary : .red)
                }
            }

            if isAdding {
                Section { ProgressView("Contacting mesh…") }
            }
        }
    }

    // MARK: - QR scanner tab

    private var qrScannerView: some View {
        QRScannerView { scanned in
            parseQRPayload(scanned)
        }
        .frame(maxWidth: .infinity, maxHeight: 360)
        .cornerRadius(16)
        .padding()
    }

    // MARK: - Actions

    private func addContact() {
        let trimmedId = nodeId.trimmingCharacters(in: .whitespaces)
        let name = displayName.trimmingCharacters(in: .whitespaces).isEmpty
            ? trimmedId.prefix(8).description
            : displayName.trimmingCharacters(in: .whitespaces)

        isAdding = true
        statusMessage = "Fetching public key from mesh…"

        Task {
            do {
                try await contactsManager.addContact(
                    nodeId: trimmedId,
                    displayName: name,
                    publicKeyBase64: publicKey.isEmpty ? nil : publicKey
                )
                await MainActor.run {
                    isAdding = false
                    statusMessage = nil
                    addedSuccessfully = true
                }
            } catch {
                await MainActor.run {
                    isAdding = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func parseQRPayload(_ payload: String) {
        // Expected format: elysium://<nodeId>?name=<displayName>&pk=<pubKey>
        // Or just a bare node_id.
        if let url = URL(string: payload), url.scheme == "elysium" {
            nodeId = url.host ?? ""
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            displayName = comps?.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
            publicKey = comps?.queryItems?.first(where: { $0.name == "pk" })?.value ?? ""
        } else {
            nodeId = payload
        }
        selectedTab = .enterID
        if !nodeId.isEmpty { addContact() }
    }
}

// MARK: - QR Code scanner (AVFoundation)

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private var captureSession: AVCaptureSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureSession?.startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showPermissionError()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func showPermissionError() {
        let label = UILabel()
        label.text = "Camera permission required"
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let string = obj.stringValue else { return }
        captureSession?.stopRunning()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        onScan?(string)
    }
}
