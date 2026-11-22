import SwiftUI
import UIKit

struct LicenseActivationView: View {
    @ObservedObject var manager: LicenseManager
    @State private var key = ""
    @State private var showAdminLogin = false
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

                            headerSection

                            activationCard

                            Spacer(minLength: 42)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 28)
                        .onChange(of: keyFocused) { focused in
                            guard focused else { return }
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("activation-card", anchor: .center)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAdminLogin) {
            AdminLoginSheet(manager: manager)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 5) {
            Text("MUY")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)

            Text("Nguyen Minh Huy • Version 1.1.1")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            Text("Package: Muy • 1-Day License")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.95))
                .padding(.top, 3)
        }
    }

    private var activationCard: some View {
        VStack(spacing: 15) {
            statusHeaderRow

            Text("Nhập key 1 ngày của Muy hoặc bấm chọn Key có sẵn.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)

            keyInputField
                .id("license-field")

            presetKeyButton

            Toggle("Ghi nhớ key trên thiết bị này", isOn: $manager.rememberKey)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .tint(AppTheme.accent)

            verifyButton

            if let message = manager.message {
                messageBanner(message)
            }

            footerActions
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .id("activation-card")
    }

    private var statusHeaderRow: some View {
        HStack(spacing: 10) {
            let iconName: String = manager.isBusy ? "arrow.triangle.2.circlepath" : "key.fill"
            let titleText: String = manager.isBusy ? "Đang xác thực..." : "Yêu cầu Key (1 Ngày)"
            Image(systemName: iconName)
                .foregroundStyle(AppTheme.secondaryAccent)
                .font(.system(size: 16, weight: .bold))
            Text(titleText)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var keyInputField: some View {
        TextField("Nhập key (VD: MUY-1DAY)", text: $key)
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
    }

    private var presetKeyButton: some View {
        let labelText = "Dùng key có sẵn 1 ngày (\(LicenseManager.defaultPresetKey))"
        return Button {
            key = LicenseManager.defaultPresetKey
        } label: {
            presetKeyButtonLabel(text: labelText)
        }
        .buttonStyle(.plain)
    }

    private func presetKeyButtonLabel(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "key.viewfinder")
            Text(text)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.8))
    }

    private var verifyButton: some View {
        let isEmpty = key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isDisabled = isEmpty || manager.isBusy
        let buttonTitle: String = manager.isBusy ? "ĐANG KIỂM TRA…" : "XÁC NHẬN & TIẾP TỤC"
        let iconName: String = manager.isBusy ? "hourglass" : "checkmark.shield.fill"

        return Button(action: activate) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                Text(buttonTitle)
            }
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: AppTheme.accent.opacity(0.30), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isEmpty ? 0.48 : 1)
    }

    private func messageBanner(_ text: String) -> some View {
        let color: Color = manager.isActive ? .green.opacity(0.95) : .red.opacity(0.95)
        return Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: 16) {
            Button("Liên hệ Nguyen Minh Huy") {
                if let url = URL(string: "https://zalo.me/0569928928") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.secondaryAccent)
            .buttonStyle(.plain)

            Text("•")
                .foregroundStyle(.white.opacity(0.35))

            Button {
                showAdminLogin = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.key.fill")
                    Text("Admin Login")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow.opacity(0.9))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func activate() {
        keyFocused = false
        manager.activate(key: key)
    }
}

struct AdminLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: LicenseManager
    @State private var password = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nguyen Minh Huy • Admin Login") {
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
                    Text("Đăng nhập thành công sẽ mở thẳng vào hệ thống của Muy và bật Bảng Quản Trị Admin trong Cài đặt.")
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
