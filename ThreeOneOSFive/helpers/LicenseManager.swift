import Combine
import Foundation
import Security
import UIKit

private struct RemoteKeyVerifyPayload: Decodable {
    let ok: Bool
    let message: String?
    let error: String?
    let expires_at: String?
}

@MainActor
final class LicenseManager: ObservableObject {
    // Đổi thành URL server Python / Cloudflare Tunnel / container của bạn (không có dấu / ở cuối)
    static let serverBaseURL = "https://your-key-server-url.example.com"

    @Published private(set) var expirationDate: Date?
    @Published private(set) var isActive = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published var rememberKey = true

    private let service = "com.tiendat.develop.activation"
    private let keyAccount = "license-key"
    private let expiresAccount = "license-expires-at"
    private var lastAttemptAt: Date?

    init() {
        restoreSavedSession()
    }

    var hasRememberedKey: Bool {
        guard let saved = string(for: keyAccount), !saved.isEmpty else { return false }
        if let exp = expirationDate, Date() > exp {
            return false
        }
        return true
    }

    static var currentDeviceId: String {
        if let idfv = UIDevice.current.identifierForVendor?.uuidString, !idfv.isEmpty {
            return idfv
        }
        return UIDevice.current.name
    }

    func beginLaunchSession() {
        restoreSavedSession()
        message = isActive ? "Ready to use" : "Key required -- enter your access key"
    }

    func activate(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        if let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < 1 {
            message = "Please wait a moment before trying again"
            return
        }
        lastAttemptAt = Date()

        let base = Self.serverBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/verify") else {
            isActive = false
            message = "Invalid key server URL"
            return
        }

        isBusy = true
        message = "Checking access key…"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "key": trimmed,
            "device_id": Self.currentDeviceId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false

                if let error = error {
                    self.isActive = false
                    self.message = "Network error: \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let decoded = try? JSONDecoder().decode(RemoteKeyVerifyPayload.self, from: data) else {
                    self.isActive = false
                    self.message = "Invalid server response"
                    return
                }

                if decoded.ok {
                    if let expStr = decoded.expires_at, let expDate = Self.parseISO8601(expStr) {
                        self.expirationDate = expDate
                        if self.rememberKey {
                            self.save(expStr, for: self.expiresAccount)
                        }
                    } else {
                        self.expirationDate = nil
                    }

                    if self.rememberKey {
                        self.save(trimmed, for: self.keyAccount)
                    } else {
                        self.delete(self.keyAccount)
                        self.delete(self.expiresAccount)
                    }

                    self.isActive = true
                    self.message = decoded.message ?? "Activated successfully"
                } else {
                    self.isActive = false
                    self.message = decoded.message ?? decoded.error ?? "Invalid access key"
                }
            }
        }.resume()
    }

    func rememberedKey() -> String? {
        string(for: keyAccount)
    }

    func refresh() {
        restoreSavedSession()
        message = isActive ? "Ready to use" : "Key required -- enter your access key"
    }

    func deactivate() {
        delete(keyAccount)
        delete(expiresAccount)
        expirationDate = nil
        isActive = false
        message = "Activation removed from this device"
    }

    private func restoreSavedSession() {
        if let expStr = string(for: expiresAccount), let expDate = Self.parseISO8601(expStr) {
            self.expirationDate = expDate
            if Date() > expDate {
                self.isActive = false
                return
            }
        } else {
            self.expirationDate = nil
        }

        if let saved = string(for: keyAccount), !saved.isEmpty {
            self.isActive = true
        } else {
            self.isActive = false
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: value) { return d }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func save(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
