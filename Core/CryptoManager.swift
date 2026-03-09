import CryptoKit
import Foundation
import Security

enum CryptoError: LocalizedError {
    case keychainRead(OSStatus)
    case keychainWrite(OSStatus)
    case invalidPublicKey
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .keychainRead(let s):  return "Keychain read failed: \(s)"
        case .keychainWrite(let s): return "Keychain write failed: \(s)"
        case .invalidPublicKey:     return "Invalid recipient public key"
        case .encryptionFailed:     return "Encryption failed"
        case .decryptionFailed:     return "Decryption failed"
        }
    }
}

final class CryptoManager {
    static let shared = CryptoManager()

    private let keyTag = "com.borisgraudt.elysium.identity.v1"

    // MARK: - Identity keypair

    /// Loads existing private key from Keychain, or generates and stores a new one.
    func loadOrCreatePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try? loadPrivateKey() { return existing }
        let fresh = Curve25519.KeyAgreement.PrivateKey()
        try savePrivateKey(fresh)
        return fresh
    }

    var publicKeyBase64: String {
        get throws {
            let key = try loadOrCreatePrivateKey()
            return key.publicKey.rawRepresentation.base64EncodedString()
        }
    }

    // MARK: - Encryption

    /// Encrypt `plaintext` so only the owner of `recipientPublicKeyBase64` can read it.
    func encrypt(_ plaintext: String, recipientPublicKeyBase64: String) throws -> Data {
        guard let recipientRaw = Data(base64Encoded: recipientPublicKeyBase64) else {
            throw CryptoError.invalidPublicKey
        }
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientRaw)
        let myKey = try loadOrCreatePrivateKey()

        let sharedSecret = try myKey.sharedSecretFromKeyAgreement(with: recipientKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("elysium-e2e-v1".utf8),
            outputByteCount: 32
        )

        guard let plainData = plaintext.data(using: .utf8) else { throw CryptoError.encryptionFailed }
        let sealed = try AES.GCM.seal(plainData, using: symmetricKey)
        guard let combined = sealed.combined else { throw CryptoError.encryptionFailed }
        return combined
    }

    // MARK: - Decryption

    /// Decrypt ciphertext produced by the sender's `encrypt(_:recipientPublicKeyBase64:)`.
    func decrypt(_ ciphertext: Data, senderPublicKeyBase64: String) throws -> String {
        guard let senderRaw = Data(base64Encoded: senderPublicKeyBase64) else {
            throw CryptoError.invalidPublicKey
        }
        let senderKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderRaw)
        let myKey = try loadOrCreatePrivateKey()

        let sharedSecret = try myKey.sharedSecretFromKeyAgreement(with: senderKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("elysium-e2e-v1".utf8),
            outputByteCount: 32
        )

        let sealed = try AES.GCM.SealedBox(combined: ciphertext)
        let plainData = try AES.GCM.open(sealed, using: symmetricKey)
        guard let text = String(data: plainData, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }
        return text
    }

    // MARK: - Keychain helpers

    private func savePrivateKey(_ key: Curve25519.KeyAgreement.PrivateKey) throws {
        let data = key.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        // Delete any existing entry first.
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CryptoError.keychainWrite(status) }
    }

    private func loadPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CryptoError.keychainRead(status)
        }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }
}
