import Foundation
import Security

/// Where the library server's password is kept: the Keychain on a device; memory in demo
/// scenarios and tests.
protocol PasswordStore: AnyObject {
    var password: String? { get }
    func setPassword(_ password: String?) throws
}

/// One generic-password item, readable after the first unlock and never leaving this device
/// (not in backups, not in iCloud Keychain).
final class KeychainPasswordStore: PasswordStore {
    struct Failure: Error {
        let status: OSStatus
    }

    private let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.pbordjadze.reader.library",
        kSecAttrAccount as String: "library-server",
    ]

    var password: String? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String?) throws {
        SecItemDelete(item as CFDictionary)
        guard let password, !password.isEmpty else { return }
        var add = item
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}

final class MemoryPasswordStore: PasswordStore {
    private(set) var password: String?

    init(password: String? = nil) {
        self.password = password
    }

    func setPassword(_ password: String?) throws {
        self.password = password?.isEmpty == false ? password : nil
    }
}
