import SwiftUI
import UIKit

struct LicenseActivationView: View {
    @ObservedObject var manager: LicenseManager
    @State private var key = ""
    @State private var showAdminLogin = false
    @State private var adminPassInput = ""
    @State private var adminError: String?
    @FocusState private var keyFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedHyperBackdrop()
                    .ignoresSafeArea()

                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 36)

                            Text("TIENDAT")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .tracking(1.4)
                                .foregroundStyle(.white)

                            Text("Version: 1.1.1")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.top, 5)

                            Text("Package: TienDat • 1-Day License")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.9))
                                .padding(.top, 8)

                            VStack(spacing: 15) {
                                HStack(spacing: 10) {
                                    Image(systemName: manager.isBusy ? "arrow.triangle.2.circlepath" : "key.fill")
                                        .foregroundStyle(AppTheme.secondaryAccent)
                                        .font(.system(size: 16, weight: .bold))
                                    Text(manager.isBusy ? "Verifying..." : "Key required (1 Day)")
                                        .font(.system(size: 16, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                }

                                Text("Nhập key có sẵn (hạn 1 ngày) hoặc bấm AutoGen để tạo key mới.")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                TextField("License key (VD: TienDat)", text: $key)
                                    .focused($keyFocused)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .onSubmit { activate() }
                                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 54)
                                    .background(Color.gray.opacity(0.22), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(AppTheme.accent.opacity(0.48), lineWidth: 1))
                                    .id("license-field")

                                // Hàng nút AutoGen Key 1 Day & Key có sẵn
                                HStack(spacing: 10) {
                                    Button {
                                        let generated = manager.autoGenerateKey(durationHours: 24)
                                        key = generated.code
                                        UIPasteboard.general.string = generated.code
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "wand.and.stars")
                                            Text("AutoGen Key (1D)")
                                        }
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        key = LicenseManager.defaultPresetKey
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "key.viewfinder")
                                            Text("Key mặc định")
                                        }
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                                    }
                                    .buttonStyle(.plain)
                                }

                                Toggle("Remember key on this device", isOn: $manager.rememberKey)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .tint(AppTheme.accent)

                                Button(action: activate) {
                                    HStack(spacing: 9) {
                                        Image(systemName: manager.isBusy ? "hourglass" : "checkmark.shield.fill")
                                        Text(manager.isBusy ? "VERIFYING…" : "VERIFY AND CONTINUE")
                                    }
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .shadow(color: AppTheme.accent.opacity(0.30), radius: 14, y: 7)
                                }
                                .buttonStyle(.plain)
                                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
                                .opacity(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.48 : 1)

                                if let message = manager.message {
                                    Text(message)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(manager.isActive ? .green.opacity(0.95) : .red.opacity(0.95))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.gray.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                HStack(spacing: 16) {
                                    Button("Contact Admin (Zalo)") {
                                        if let url = URL(string: "https://zalo.me/0986321175") {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryAccent)
                                    .buttonStyle(.plain)

                                    Text("•")
                                        .foregroundStyle(.white.opacity(0.35))

                                    Button {
                                        adminPassInput = ""
                                        adminError = nil
                                        showAdminLogin = true
                                    } label: {
                                        Label("Admin Login", systemImage: "person.badge.key.fill")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(.yellow.opacity(0.9))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 4)
                            }
                            .padding(20)
                            .background(.ultraThinMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
                            .padding(.horizontal, 22)
                            .padding(.top, 24)
                            .id("activation-card")

                            Spacer(minLength: 42)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 28)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: keyFocused) { focused in
                        guard focused else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("activation-card", anchor: .center) }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAdminLogin) {
            AdminLoginSheet(manager: manager)
        }
    }

    private func activate() {
        keyFocused = false
        manager.activate(key: key)
    }
}

// MARK: - SHEET ĐĂNG NHẬP ADMIN
struct AdminLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: LicenseManager
    @State private var password = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Đăng nhập quản trị viên") {
                    SecureField("Mật khẩu Admin", text: $password)
                        .submitLabel(.done)
                        .onSubmit(submitAdmin)

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Đăng nhập Admin") {
                        submitAdmin()
                    }
                    .font(.headline)
                    .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Sau khi đăng nhập Admin, bạn có thể vào thẳng app và mở Bảng Admin trong tab Cài đặt để AutoGen / quản lý key.")
                }
            }
            .navigationTitle("Admin Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submitAdmin() {
        if manager.loginAdmin(password: password) {
            dismiss()
        } else {
            errorText = "Mật khẩu Admin không đúng."
        }
    }
}
