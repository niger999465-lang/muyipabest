import Combine
import CryptoKit
import Foundation
import Security
import SwiftUI

struct GeneratedKeyItem: Identifiable, Codable, Equatable {
    let id: UUID
    let code: String
    let durationHours: Int // 0 = vĩnh viễn
    let createdAt: Date
    var activatedAt: Date?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }

    var durationLabel: String {
        if durationHours == 0 { return "Vĩnh viễn" }
        if durationHours % 24 == 0 { return "\(durationHours / 24) ngày" }
        return "\(durationHours) giờ"
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    // Key có sẵn hạn 1 ngày (24 giờ)
    static let defaultPresetKey = "MUY-1DAY"
    // Mật khẩu đăng nhập Admin (đổi theo ý bạn)
    static let adminPassword = "muyadmin123"
    // Khóa bí mật HMAC-SHA256 (phải khớp với file Python sinh 1000 key)
    static let hmacSecret = "MUY_NGUYEN_MINH_HUY_HMAC_SECRET_2026"

    @Published private(set) var expirationDate: Date?
    @Published private(set) var isActive = false
    @Published private(set) var isAdmin = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published var rememberKey = true
    @Published private(set) var generatedKeys: [GeneratedKeyItem] = []

    private let service = "com.muy.nguyenminhhuy.activation"
    private let keyAccount = "license-key"
    private let expiresAccount = "license-expires-at"
    private let adminAccount = "license-is-admin"
    private let keysVaultAccount = "license-generated-vault"
    private let usedKeysDefaultsKey = "muy_used_keys_v1"

    private var expiryTimer: Timer?

    init() {
        loadGeneratedKeys()
        restoreSavedSession()
        startExpiryWatcher()
    }

    deinit {
        expiryTimer?.invalidate()
    }

    // MARK: - Session & Kiểm tra hết hạn tự động

    func beginLaunchSession() {
        restoreSavedSession()
        if isAdmin {
            message = "Nguyen Minh Huy • Admin mode active"
        } else if isActive {
            message = "Muy System ready"
        } else {
            message = "Yêu cầu key • Nhập key 1 ngày để tiếp tục"
        }
    }

    func refresh() {
        restoreSavedSession()
    }

    private func startExpiryWatcher() {
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkExpirationNow()
            }
        }
    }

    private func checkExpirationNow() {
        guard !isAdmin, isActive, let exp = expirationDate else { return }
        if Date() > exp {
            deactivate(reason: "Key 1 ngày đã hết hạn. Vui lòng nhập key mới.")
        }
    }

    private func restoreSavedSession() {
        if string(for: adminAccount) == "1" {
            isAdmin = true
            isActive = true
            expirationDate = nil
            return
        }

        isAdmin = false
        guard let savedKey = string(for: keyAccount), !savedKey.isEmpty else {
            isActive = false
            expirationDate = nil
            return
        }

        if let expStr = string(for: expiresAccount), let expInterval = Double(expStr) {
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
        } else {
            isActive = false
            expirationDate = nil
        }
    }

    // MARK: - Xác thực chữ ký HMAC-SHA256 cho danh sách key hàng loạt (MUY-XXXXXXXX-YYYYYY)

    static func isValidSignedKey(_ rawKey: String) -> Bool {
        let normalized = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parts = normalized.split(separator: "-")
        guard parts.count == 3,
              parts[0] == "MUY",
              parts[1].count == 8,
              parts[2].count == 6 else {
            return false
        }

        let base = "\(parts[0])-\(parts[1])"
        let givenSig = String(parts[2])

        let keyData = SymmetricKey(data: Data(hmacSecret.utf8))
        let authCode = HMAC<SHA256>.authenticationCode(for: Data(base.utf8), using: keyData)
        let expectedSig = authCode.map { String(format: "%02X", $0) }.joined().prefix(6)

        return givenSig == expectedSig
    }

    // MARK: - Kích hoạt Key

    func activate(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        isBusy = true
        message = "Đang xác thực key..."

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.isBusy = false

            // 1. Key trong kho AutoGen của Admin
            if let idx = self.generatedKeys.firstIndex(where: { $0.code.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                var item = self.generatedKeys[idx]

                if let existingExp = item.expiresAt, Date() > existingExp {
                    self.isActive = false
                    self.message = "Key này đã hết hạn."
                    return
                }

                let expDate: Date?
                if item.durationHours == 0 {
                    expDate = nil
                } else if let existingExp = item.expiresAt {
                    expDate = existingExp
                } else {
                    let newExp = Date().addingTimeInterval(TimeInterval(item.durationHours * 3600))
                    item.activatedAt = Date()
                    item.expiresAt = newExp
                    self.generatedKeys[idx] = item
                    self.saveGeneratedKeys()
                    expDate = newExp
                }

                self.completeActivation(key: item.code, expiresAt: expDate)
                return
            }

            // 2. Key có sẵn hạn 1 ngày (24 giờ)
            if trimmed.caseInsensitiveCompare(Self.defaultPresetKey) == .orderedSame {
                let normalized = trimmed.lowercased()
                if self.isKeyAlreadyConsumed(normalized) {
                    self.isActive = false
                    self.message = "Key mặc định 1 ngày đã được dùng trên thiết bị này."
                    return
                }
                self.markKeyConsumed(normalized)
                let expDate = Date().addingTimeInterval(24 * 3600)
                self.completeActivation(key: Self.defaultPresetKey, expiresAt: expDate)
                return
            }

            // 3. Key random ký HMAC-SHA256 (hạn 1 ngày kể từ lần kích hoạt đầu)
            let upper = trimmed.uppercased()
            if Self.isValidSignedKey(upper) {
                let normalized = upper.lowercased()
                if self.isKeyAlreadyConsumed(normalized) {
                    self.isActive = false
                    self.message = "Key này đã được kích hoạt trước đó."
                    return
                }
                self.markKeyConsumed(normalized)
                let expDate = Date().addingTimeInterval(24 * 3600)
                self.completeActivation(key: upper, expiresAt: expDate)
                return
            }

            self.isActive = false
            self.message = "Key không hợp lệ hoặc đã hết hạn."
        }
    }

    private func completeActivation(key: String, expiresAt: Date?) {
        isAdmin = false
        delete(adminAccount)
        expirationDate = expiresAt
        isActive = true

        if rememberKey {
            save(key, for: keyAccount)
            if let exp = expiresAt {
                save(String(exp.timeIntervalSince1970), for: expiresAccount)
            } else {
                save(String(Date.distantFuture.timeIntervalSince1970), for: expiresAccount)
            }
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

    // MARK: - AutoGen Key

    @discardableResult
    func autoGenerateKey(durationHours: Int = 24) -> GeneratedKeyItem {
        let randPart = Self.randomHex(length: 8)
        let base = "MUY-\(randPart)"
        let keyData = SymmetricKey(data: Data(Self.hmacSecret.utf8))
        let authCode = HMAC<SHA256>.authenticationCode(for: Data(base.utf8), using: keyData)
        let sig = authCode.map { String(format: "%02X", $0) }.joined().prefix(6)
        let code = "\(base)-\(sig)"

        let item = GeneratedKeyItem(
            id: UUID(),
            code: code,
            durationHours: durationHours,
            createdAt: Date(),
            activatedAt: nil,
            expiresAt: nil
        )
        generatedKeys.insert(item, at: 0)
        saveGeneratedKeys()
        return item
    }

    func deleteGeneratedKey(_ item: GeneratedKeyItem) {
        generatedKeys.removeAll { $0.id == item.id }
        saveGeneratedKeys()
    }

    func resetPresetKeyUsage() {
        UserDefaults.standard.removeObject(forKey: usedKeysDefaultsKey)
    }

    // MARK: - Admin Login & Logout

    @discardableResult
    func loginAdmin(password: String) -> Bool {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == Self.adminPassword else {
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
        if !isActive {
            message = "Đã đăng xuất Admin"
        }
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

    // MARK: - Lưu trữ

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

    private func loadGeneratedKeys() {
        guard let raw = string(for: keysVaultAccount),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([GeneratedKeyItem].self, from: data) else {
            generatedKeys = []
            return
        }
        generatedKeys = decoded
    }

    private func saveGeneratedKeys() {
        guard let data = try? JSONEncoder().encode(generatedKeys),
              let raw = String(data: data, encoding: .utf8) else { return }
        save(raw, for: keysVaultAccount)
    }

    private static func randomHex(length: Int) -> String {
        let chars = Array("ABCDEF0123456789")
        return String((0..<length).compactMap { _ in chars.randomElement() })
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
