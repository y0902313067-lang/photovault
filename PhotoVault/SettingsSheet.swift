import SwiftUI

// MARK: - 齒輪選單

struct SettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var openEdit = false
    @State private var openAccount = false
    @State private var openRedeem = false
    @State private var showLogout = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Capsule().fill(Color.white.opacity(0.18))
                    .frame(width: 38, height: 4)
                    .padding(.top, 8)

                row(icon: "person.crop.circle", title: "編輯個人主頁",
                    sub: "改頭貼、改名字") { openEdit = true }
                row(icon: "checkmark.shield", title: "帳號狀態",
                    sub: "權限與帳號資訊") { openAccount = true }
                row(icon: "ticket", title: "兌換碼",
                    sub: "輸入兌換碼領取稱號或會員等級") { openRedeem = true }
                row(icon: "bubble.left.and.bubble.right.fill", title: "聯繫客服",
                    sub: "遇到問題或有建議，直接找我們") {
                    if let url = URL(string: "https://lin.ee/TYSCkcO") { openURL(url) }
                }

                Button {
                    showLogout = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(red: 1.0, green: 0.45, blue: 0.5).opacity(0.14))
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.5))
                        }
                        .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("登出帳號")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.5))
                            Text("登出後要重新註冊才能再用")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.32))
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.5).opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color(red: 1.0, green: 0.45, blue: 0.5).opacity(0.16), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.045, green: 0.06, blue: 0.085).ignoresSafeArea())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .navigationDestination(isPresented: $openEdit) { EditProfileView() }
            .navigationDestination(isPresented: $openRedeem) { RedeemView() }
        }
        .sheet(isPresented: $openAccount) { AccountStatusView() }
        .presentationDetents([.medium, .large])
        .alert("確定要登出？", isPresented: $showLogout) {
            Button("登出", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    store.logout()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("登出後會回到註冊頁，資料不會保留在手機上。")
        }
    }

    private func row(icon: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TT.mint.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TT.mint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.22))
            }
            .padding(.horizontal, 14)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 編輯個人主頁

struct EditProfileView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var saving = false
    @State private var tip: String?
    @State private var showAvatar = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button { showAvatar = true } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            if let img = store.avatarImage {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                            } else {
                                Circle().fill(Color.white.opacity(0.07))
                                    .frame(width: 96, height: 96)
                                Image(systemName: "person.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            Circle()
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                .frame(width: 96, height: 96)
                        }
                        Text("點一下更換頭貼")
                            .font(.system(size: 11.5))
                            .foregroundStyle(TT.mint.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 7) {
                    Text("名字")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    TextField("", text: $name)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.white.opacity(0.055))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                    Text("最多 8 個字。改名不會影響你的帳號。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.28))
                }

                if let tip {
                    Text(tip)
                        .font(.system(size: 12))
                        .foregroundStyle(tip.hasPrefix("已") ? TT.mint : TT.rose)
                }

                Button {
                    save()
                } label: {
                    ZStack {
                        Capsule().fill(TT.mint)
                        if saving {
                            ProgressView().tint(Color(red: 0.03, green: 0.09, blue: 0.08))
                        } else {
                            Text("儲存")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                        }
                    }
                    .frame(height: 48)
                }
                .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(red: 0.045, green: 0.06, blue: 0.085).ignoresSafeArea())
        .navigationTitle("編輯個人主頁")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAvatar) { AvatarPickerSheet() }
        .onAppear { name = store.nickname }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        tip = nil
        Task {
            let err = await store.changeNickname(name)
            await MainActor.run {
                saving = false
                if let err {
                    tip = err
                } else {
                    tip = "已更新"
                }
            }
        }
    }
}

// MARK: - 帳號狀態

struct AccountStatusView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProfileView(embedded: false)
    }
}

// MARK: - 兌換碼

struct RedeemView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var busy = false
    @State private var tip: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(TT.amber)
                    Text("輸入兌換碼")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("每組兌換碼只能使用一次")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.top, 20)

                TextField("兌換碼", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.9)
                    )
                    .padding(.horizontal, 4)

                if let tip {
                    Text(tip)
                        .font(.system(size: 12))
                        .foregroundStyle(tip.hasPrefix("兌換成功") ? TT.mint : TT.rose)
                        .multilineTextAlignment(.center)
                }

                Button {
                    submit()
                } label: {
                    ZStack {
                        Capsule().fill(TT.mint)
                        if busy {
                            ProgressView().tint(Color(red: 0.03, green: 0.09, blue: 0.08))
                        } else {
                            Text("兌換")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                        }
                    }
                    .frame(height: 48)
                }
                .disabled(busy || code.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(red: 0.045, green: 0.06, blue: 0.085).ignoresSafeArea())
        .navigationTitle("兌換碼")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        tip = nil
        Task {
            let err = await store.redeem(code)
            await MainActor.run {
                busy = false
                if let err {
                    tip = err
                } else {
                    tip = "兌換成功，獎勵已經到帳"
                    code = ""
                }
            }
        }
    }
}
