import SwiftUI
import PhotosUI
import UIKit

// MARK: - 背景

struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.18, green: 0.42, blue: 0.85).opacity(0.55),
                                    .clear],
                           center: .init(x: 0.12, y: 0.02),
                           startRadius: 8, endRadius: 460)
                .ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.42, green: 0.28, blue: 0.85).opacity(0.42),
                                    .clear],
                           center: .init(x: 0.95, y: 0.12),
                           startRadius: 8, endRadius: 420)
                .ignoresSafeArea()
        }
    }
}

// MARK: - 入口

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Backdrop()
            switch store.stage {
            case .register:  RegisterView()
            case .avatar:    AvatarView()
            case .uploading: UploadingView()
            case .home:      HomeView()
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: store.stage)
        .onChange(of: scenePhase) { phase in
            if phase == .active { store.resumeIfNeeded() }
        }
    }
}

// MARK: - 共用外观

private struct FieldBox: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var limit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                if let limit {
                    Spacer()
                    Text("\(text.count)/\(limit)")
                        .font(.system(size: 11))
                        .foregroundStyle(text.count > limit ? Color.red.opacity(0.9) : .white.opacity(0.35))
                }
            }
            Group {
                if secure {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.28)))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.28)))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .onChange(of: text) { newValue in
                if let limit, newValue.count > limit {
                    text = String(newValue.prefix(limit))
                }
            }
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(enabled ? Color(red: 0.02, green: 0.08, blue: 0.18) : .white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            enabled
                            ? LinearGradient(colors: [Color(red: 0.46, green: 0.72, blue: 1.0),
                                                      Color(red: 0.36, green: 0.55, blue: 1.0),
                                                      Color(red: 0.53, green: 0.42, blue: 1.0)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom)
                        )
                )
                .shadow(color: enabled ? Color(red: 0.36, green: 0.55, blue: 1.0).opacity(0.45) : .clear,
                        radius: 18, y: 8)
        }
        .disabled(!enabled)
    }
}

// MARK: - 注册 / 登入

struct RegisterView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1.0),
                                                          Color(red: 0.53, green: 0.42, blue: 1.0)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 66, height: 66)
                            .shadow(color: Color(red: 0.36, green: 0.5, blue: 1.0).opacity(0.5), radius: 22, y: 10)
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 44)

                    Text(store.isLoginMode ? "登入帳號" : "建立帳號")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(store.isLoginMode ? "用原本的帳號密碼登入，照片都還在" : "填好資料就可以開始備份相簿")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 26)
                }

                VStack(spacing: 16) {
                    if store.isLoginMode {
                        FieldBox(title: "帳號", placeholder: "註冊時填的帳號", text: $store.account)
                        FieldBox(title: "密碼", placeholder: "註冊時填的密碼", text: $store.password, secure: true)
                    } else {
                        FieldBox(title: "暱稱（8 字內）", placeholder: "例如：小美", text: $store.nickname, limit: 8)
                        FieldBox(title: "帳號", placeholder: "隨便填，沒有限制", text: $store.account)
                        FieldBox(title: "密碼", placeholder: "隨便填，沒有限制", text: $store.password, secure: true)
                        FieldBox(title: "再次輸入密碼", placeholder: "再填一次", text: $store.password2, secure: true)

                        if !store.password2.isEmpty && !store.matchOK {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("兩次密碼不一致")
                                Spacer()
                            }
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.5))
                        }
                    }
                }
                .padding(.horizontal, 22)

                if let err = store.errorText, !err.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(err)
                        Spacer()
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.5))
                    .padding(.horizontal, 26)
                    .padding(.top, 14)
                }

                PrimaryButton(title: store.isLoginMode ? (store.busy ? "登入中…" : "登入") : "下一步",
                              enabled: store.isLoginMode ? (store.loginFormOK && !store.busy) : store.formOK) {
                    if store.isLoginMode {
                        store.doLogin()
                    } else {
                        store.goAvatarStep()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)

                Button {
                    store.switchMode(toLogin: !store.isLoginMode)
                } label: {
                    HStack(spacing: 4) {
                        Text(store.isLoginMode ? "還沒有帳號？" : "已經註冊過？")
                            .foregroundStyle(.white.opacity(0.45))
                        Text(store.isLoginMode ? "建立新帳號" : "登入已有帳號")
                            .foregroundStyle(Color(red: 0.55, green: 0.75, blue: 1.0))
                    }
                    .font(.system(size: 13.5))
                }
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - 头像

struct AvatarView: View {
    @EnvironmentObject var store: AppStore
    @State private var picked: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("設定頭像")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("頭像不能略過，點右下角的 + 選一張")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 62)

            Spacer(minLength: 20)

            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
                    if let img = store.avatarImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 62, weight: .light))
                            .foregroundStyle(.white.opacity(0.22))
                    }
                }
                .frame(width: 188, height: 188)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

                Button {
                    Task { await store.requestPhotoPermission() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(red: 0.46, green: 0.72, blue: 1.0),
                                                          Color(red: 0.42, green: 0.35, blue: 0.95)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 58, height: 58)
                            .shadow(color: Color(red: 0.4, green: 0.55, blue: 1.0).opacity(0.55), radius: 14, y: 6)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .offset(x: 6, y: 6)
            }

            Spacer(minLength: 20)

            PrimaryButton(title: "下一步", enabled: store.canContinueAvatar) {
                store.persistAvatar()
                store.startUploading()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 44)
        }
        .photosPicker(isPresented: $store.showAvatarPicker, selection: $picked, matching: .images)
        .onChange(of: picked) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { store.setAvatar(img) }
                }
            }
        }
        .alert("需要相簿權限", isPresented: $store.needsSettings) {
            Button("去設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("到「設定 → 隱私權與安全性 → 照片」把存取權打開，才能選頭像和上傳照片。")
        }
    }
}

// MARK: - 上传

private enum PVTheme {
    static let blue   = Color(red: 0.42, green: 0.70, blue: 1.00)
    static let indigo = Color(red: 0.44, green: 0.42, blue: 1.00)
    static let violet = Color(red: 0.66, green: 0.42, blue: 1.00)
    static let teal   = Color(red: 0.36, green: 0.86, blue: 0.86)

    static var ring: LinearGradient {
        LinearGradient(colors: [teal, blue, indigo, violet],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 上传（加载页）

struct UploadingView: View {
    @EnvironmentObject var store: AppStore

    @State private var spin = false
    @State private var breathe = false
    @State private var drift = false

    private var percent: Int { Int((store.progress * 100).rounded()) }

    private var clamped: Double {
        min(max(store.progress, 0.004), 1)
    }

    private var phaseIcon: String {
        switch store.phaseIndex {
        case 0: return "icloud.and.arrow.up"
        case 1: return "person.badge.shield.checkmark"
        case 2: return "checkmark.seal"
        case 3: return "lock.shield"
        case 4: return "checkmark.seal.fill"
        default: return "shippingbox"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            Spacer(minLength: 14)
            ringView
            statusPill.padding(.top, 6)
            stepBar.padding(.top, 22)
            Spacer()
            footNote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(blobs.ignoresSafeArea())
        .onAppear(perform: startAnimations)
    }

    // 左上角品牌：薄荷龍 logo + 名稱
    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image("MintDragon")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: PVTheme.teal.opacity(0.4), radius: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("薄荷龍科技")
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text("MINT DRAGON TECH")
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.7)
                    .foregroundColor(.white.opacity(0.32))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 26)
        .padding(.trailing, 20)
        .padding(.top, 10)
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) { spin = true }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        drift = true
    }

    // 缓慢飘动的光斑
    private var blobs: some View {
        ZStack {
            blob(color: PVTheme.blue.opacity(0.34), side: 480, blur: 30,
                 dx: drift ? -90 : -150, dy: drift ? 10 : -110)
            blob(color: PVTheme.violet.opacity(0.30), side: 440, blur: 30,
                 dx: drift ? 150 : 90, dy: drift ? 150 : 220)
            blob(color: PVTheme.teal.opacity(0.16), side: 400, blur: 26,
                 dx: drift ? 120 : 160, dy: drift ? -160 : -70)
        }
        .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: drift)
        .allowsHitTesting(false)
    }

    private func blob(color: Color, side: CGFloat, blur: CGFloat, dx: CGFloat, dy: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear],
                                 center: .center,
                                 startRadius: 4,
                                 endRadius: side * 0.5))
            .frame(width: side, height: side)
            .blur(radius: blur)
            .offset(x: dx, y: dy)
    }

    private var headOffset: CGSize {
        let angle = clamped * 2 * Double.pi - Double.pi / 2
        return CGSize(width: CGFloat(cos(angle) * 92), height: CGFloat(sin(angle) * 92))
    }

    // 进度环
    private var ringView: some View {
        ZStack {
            glow
            dashedRing
            trackRing
            arcRing
            headDot
            centerLabel
        }
        .frame(height: 300)
    }

    private var glow: some View {
        Circle()
            .fill(RadialGradient(colors: [PVTheme.indigo.opacity(0.26), .clear],
                                 center: .center, startRadius: 30, endRadius: 150))
            .frame(width: 300, height: 300)
            .scaleEffect(breathe ? 1.06 : 0.94)
            .opacity(breathe ? 0.95 : 0.6)
    }

    private var dashedRing: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.10),
                          style: StrokeStyle(lineWidth: 1, dash: [2, 8]))
            .frame(width: 226, height: 226)
            .rotationEffect(.degrees(spin ? 360 : 0))
    }

    private var trackRing: some View {
        Circle()
            .stroke(Color.white.opacity(0.07), lineWidth: 11)
            .frame(width: 184, height: 184)
    }

    private var arcRing: some View {
        Circle()
            .trim(from: 0, to: clamped)
            .stroke(PVTheme.ring, style: StrokeStyle(lineWidth: 11, lineCap: .round))
            .frame(width: 184, height: 184)
            .rotationEffect(.degrees(-90))
            .shadow(color: PVTheme.blue.opacity(0.55), radius: 10)
            .animation(.easeInOut(duration: 0.45), value: store.progress)
    }

    private var headDot: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .shadow(color: PVTheme.blue, radius: 9)
            .overlay(Circle().stroke(PVTheme.violet.opacity(0.9), lineWidth: 2))
            .offset(headOffset)
            .animation(.easeInOut(duration: 0.45), value: store.progress)
    }

    private var centerLabel: some View {
        VStack(spacing: -2) {
            Text("\(percent)")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            Text("％")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // 状态胶囊
    private var statusPill: some View {
        HStack(spacing: 9) {
            Image(systemName: phaseIcon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(PVTheme.teal.opacity(0.9))
            Text(store.phaseText)
                .font(.system(size: 16.5, weight: .medium))
                .foregroundColor(.white.opacity(0.94))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        )
        .animation(.easeInOut(duration: 0.35), value: store.phaseText)
    }

    // 六段阶段指示
    private var stepBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { i in
                stepCapsule(i)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.phaseIndex)
    }

    private func stepCapsule(_ i: Int) -> some View {
        let active = i <= store.phaseIndex
        return Capsule()
            .fill(active ? AnyShapeStyle(PVTheme.ring) : AnyShapeStyle(Color.white.opacity(0.12)))
            .frame(width: i == store.phaseIndex ? 20 : 7, height: 5)
    }

    private var footNote: some View {
        Group {
            if store.syncStalled && !store.running {
                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.arrow.circlepath").font(.system(size: 10))
                        Text("同步還沒完成，下次打開會自動接著傳")
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.5))

                    HStack(spacing: 10) {
                        Button {
                            store.retrySync()
                        } label: {
                            Text("再試一次")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        }
                        Button {
                            store.skipToHome()
                        } label: {
                            Text("先進入主頁")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        }
                    }
                }
                .padding(.bottom, 34)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9))
                    Text("中途離開也沒關係，下次打開會自動接著傳")
                }
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.26))
                .padding(.bottom, 42)
            }
        }
    }
}

// MARK: - 主页

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showProfile = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "hammer.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white.opacity(0.22))
                Text("內容正在開發中")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .frame(maxWidth: .infinity)

            Button {
                showProfile = true
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.62, blue: 1.0),
                                                      Color(red: 0.5, green: 0.4, blue: 0.95)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 62, height: 62)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                    if let img = store.avatarImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.trailing, 22)
            .padding(.bottom, 34)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView().environmentObject(store)
        }
    }
}

// MARK: - 个人档案

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showLogout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.07))
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        if let img = store.avatarImage {
                            Image(uiImage: img).resizable().scaledToFill().clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .frame(width: 132, height: 132)
                    .padding(.top, 12)

                    VStack(spacing: 4) {
                        Text(store.nickname)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("@\(store.account)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    VStack(spacing: 0) {
                        row("帳號狀態", "已啟用")
                        Divider().background(Color.white.opacity(0.08))
                        row("相簿權限", authText)
                        Divider().background(Color.white.opacity(0.08))
                        row("同步狀態", syncText)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal, 18)

                    Button {
                        showLogout = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("登出這個帳號")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .padding(.horizontal, 18)

                    Text("登出後要重新註冊；只要不登出、不刪除 App，下次打開都會直接進主頁。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer(minLength: 30)
                }
            }
            .background(Backdrop())
            .navigationTitle("個人檔案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .presentationDetents([.large])
        .alert("確定登出？", isPresented: $showLogout) {
            Button("登出", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    store.logout()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("登出後會回到註冊頁，後台已上傳的照片不會被刪除。")
        }
    }

    private var authText: String {
        switch store.authStatus {
        case .authorized, .limited: return "已允許"
        case .denied, .restricted:  return "未允許"
        default:                    return "未設定"
        }
    }

    private var syncText: String {
        if store.running { return "同步中…" }
        if store.pendingSync { return "待續傳" }
        return "正常"
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(v).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

#Preview {
    RootView().environmentObject(AppStore())
}
