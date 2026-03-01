import CryptoKit
import Foundation
import Security

@MainActor
final class KeychainPINStore {
    enum Error: Swift.Error {
        case invalidData
        case failedToStore
    }

    private let service = "mdm.FocusNow"

    func setPIN(_ pin: String, key: String) throws {
        let salt = randomSalt()
        let hash = hashFor(pin: pin, salt: salt)
        let payload = "\(salt):\(hash)"

        guard let data = payload.data(using: .utf8) else {
            throw Error.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Error.failedToStore
        }
    }

    func hasPIN(key: String) -> Bool {
        fetchPayload(key: key) != nil
    }

    func verifyPIN(_ pin: String, key: String) -> Bool {
        guard let payload = fetchPayload(key: key) else { return false }
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }

        let expectedHash = hashFor(pin: pin, salt: parts[0])
        return expectedHash == parts[1]
    }

    private func fetchPayload(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    private func randomSalt() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    private func hashFor(pin: String, salt: String) -> String {
        let payload = "\(salt)|\(pin)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
