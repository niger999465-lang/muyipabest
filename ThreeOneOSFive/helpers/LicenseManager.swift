import Combine
import CryptoKit
import Foundation
import Security
import SwiftUI

private struct GitHubKeyRule: Decodable {
    let hours: Int
    let active: Bool
}

@MainActor
final class LicenseManager: ObservableObject {
    // Link Raw tới file keys.json trên GitHub của bạn
    static let githubKeysRawURL = "https://raw.githubusercontent.com/niger999465-lang/muy-keys/main/keys.json"
    // Nếu repo để Private, điền GitHub Fine-grained Token (chỉ quyền Read Contents) vào đây; nếu Public thì để trống ""
    static let githubReadToken = ""

    static let defaultPresetKey = "MUY-1DAY"
    static let adminPassword = "muyadmin123"
    static let hmacSecret = "MUY_NGUYEN_MINH_HUY_HMAC_SECRET_2026"

    @Published private(set) var expirationDate: Date?
    @Published private(set) var isActive = false
    @Published private(set) var isAdmin = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published var rememberKey = true

    private let service = "com.muy.nguyenminhhuy.activation"
    private let keyAccount = "license-key"
    private let expiresAccount = "license-expires-at"
    private let adminAccount = "license-is-admin"
    private let usedKeysDefaultsKey = "muy_used_keys_v1"

    init() {
        restoreSavedSession()
    }

    func beginLaunchSession() {
        restoreSavedSession()
        if isAdmin {
            message = "Nguyen Minh Huy • Admin mode active"
        } else if isActive {
            message = "Muy System ready"
        } else {
            message = "Yêu cầu key • Nhập key để tiếp tục"
        }
    }

    func refresh() {
        restoreSavedSession()
    }

    private func restoreSavedSession() {
        if string(for: adminAccount) == "1" {
            isAdmin = true
            isActive = true
            expirationDate = nil
            return
        }

        isAdmin = false
        guard let savedKey = string(for: keyAccount), !savedKey.isEmpty,
              let expStr = string(for: expiresAccount), let expInterval = Double(expStr) else {
            isActive = false
            expirationDate = nil
            return
        }

        let expDate = Date(timeIntervalSince1970: expInterval)
        if Date() > expDate {
            delete(keyAccount)
            delete(expiresAccount)
            expirationDate = nil
            isActive = false
            message = "Key đã hết hạn. Vui lòng nhập key mới."
            return
        }

        expirationDate = expDate
        isActive = true
    }

    // MARK: - Kích hoạt key từ file keys.json trên GitHub

    func activate(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        // Kiểm tra key mặc định 1 ngày offline nếu cần
        if trimmed.caseInsensitiveCompare(Self.defaultPresetKey) == .orderedSame {
            let normalized = trimmed.lowercased()
            if isKeyAlreadyConsumed(normalized) {
                isActive = false
                message = "Key mặc định 1 ngày đã được dùng trên thiết bị này."
                return
            }
            markKeyConsumed(normalized)
            completeActivation(key: Self.defaultPresetKey, expiresAt: Date().addingTimeInterval(24 * 3600))
            return
        }

        guard let baseURL = URL(string: Self.githubKeysRawURL) else {
            message = "Link GitHub keys.json không hợp lệ."
            return
        }

        // Thêm query timestamp để tránh CDN GitHub cache file cũ
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        guard let finalURL = components?.url else { return }

        isBusy = true
        message = "Đang kiểm tra key trên hệ thống Muy..."

        var request = URLRequest(url: finalURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        if !Self.githubReadToken.isEmpty {
            request.setValue("token \(Self.githubReadToken)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false

                if let error = error {
                    self.isActive = false
                    self.message = "Lỗi mạng: \(error.localizedDescription)"
                    return
                }

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    self.isActive = false
                    self.message = "Không tải được danh sách key (HTTP \(http.statusCode))."
                    return
                }

                guard let data = data,
                      let keyMap = try? JSONDecoder().decode([String: GitHubKeyRule].self, from: data) else {
                    self.isActive = false
                    self.message = "Dữ liệu keys.json trên GitHub sai định dạng."
                    return
                }

                // Tìm key không phân biệt hoa thường
                guard let matched = keyMap.first(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                    self.isActive = false
                    self.message = "Key không tồn tại trên hệ thống."
                    return
                }

                let rule = matched.value
                guard rule.active else {
                    self.isActive = false
                    self.message = "Key này đã bị khóa."
                    return
                }

                let normalized = matched.key.lowercased()
                if self.isKeyAlreadyConsumed(normalized) {
                    self.isActive = false
                    self.message = "Key này đã được sử dụng trên thiết bị này."
                    return
                }

                self.markKeyConsumed(normalized)
                let expDate: Date? = rule.hours > 0
                    ? Date().addingTimeInterval(TimeInterval(rule.hours * 3600))
                    : nil
                self.completeActivation(key: matched.key, expiresAt: expDate)
            }
        }.resume()
    }

    private func completeActivation(key: String, expiresAt: Date?) {
        isAdmin = false
        delete(adminAccount)
        expirationDate = expiresAt
        isActive = true

        if rememberKey {
            save(key, for: keyAccount)
            let expToSave = expiresAt ?? Date.distantFuture
            save(String(expToSave.timeIntervalSince1970), for: expiresAccount)
        } else {
            delete(keyAccount)
            delete(expiresAccount)
        }

        if let exp = expiresAt {
            message = "Kích hoạt thành công • Hết hạn: \(exp.formatted(date: .abbreviated, time: .shortened))"
        } else {
            message = "Kích hoạt thành công • Vĩnh viễn"
        }
    }

    // MARK: - Admin Login & Logout

    @discardableResult
    func loginAdmin(password: String) -> Bool {
        guard password.trimmingCharacters(in: .whitespacesAndNewlines) == Self.adminPassword else {
            message = "Sai mật khẩu Admin của Nguyen Minh Huy."
            return false
        }
        isAdmin = true
        isActive = true
        expirationDate = nil
        save("1", for: adminAccount)
        message = "Đã đăng nhập Admin • Nguyen Minh Huy"
        return true
    }

    func logoutAdmin() {
        delete(adminAccount)
        isAdmin = false
        restoreSavedSession()
    }

    func deactivate(reason: String = "Đã đăng xuất key khỏi thiết bị") {
        delete(keyAccount)
        delete(expiresAccount)
        delete(adminAccount)
        isAdmin = false
        expirationDate = nil
        isActive = false
        message = reason
    }

    func rememberedKey() -> String? {
        if isAdmin { return "MUY-ADMIN (Nguyen Minh Huy)" }
        return string(for: keyAccount)
    }

    private func isKeyAlreadyConsumed(_ normalizedKey: String) -> Bool {
        let list = UserDefaults.standard.stringArray(forKey: usedKeysDefaultsKey) ?? []
        return list.contains(normalizedKey)
    }

    private func markKeyConsumed(_ normalizedKey: String) {
        var list = UserDefaults.standard.stringArray(forKey: usedKeysDefaultsKey) ?? []
        if !list.contains(normalizedKey) {
            list.append(normalizedKey)
            UserDefaults.standard.set(list, forKey: usedKeysDefaultsKey)
        }
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
