import SwiftUI
import PhotosUI
import Photos
import UIKit
import AVFoundation
import UserNotifications
import CoreLocation
import CoreMotion
import Speech

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
    @State private var beat = Timer.publish(every: 180, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Backdrop()
            switch store.stage {
            case .register:  RegisterView()
            case .avatar:    AvatarView()
            case .splash:    SplashView()
            case .home:      MainTabView()
            }

            if let reward = store.rewardToast {
                rewardLayer(reward)
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .keyboardDismissBar()
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: store.stage)
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                silentPing()
            }
        }
        .onReceive(beat) { _ in
            if scenePhase == .active { silentPing() }
        }
    }

    @ViewBuilder
    private func rewardLayer(_ reward: String) -> some View {
        if reward.hasPrefix("level:"),
           let n = Int(reward.dropFirst(6)),
           let lv = MemberLevel(rawValue: n) {
            RewardPopup(title: nil, level: lv) { store.rewardToast = nil }
        } else if let def = Titles.find(reward) {
            RewardPopup(title: def, level: nil) { store.rewardToast = nil }
        }
    }

    /// 靜默定位心跳：只把位置補進後台，畫面上不出現任何提示或狀態
    private func silentPing() {
        LocationBeacon.shared.ping { lat, lon, alt, acc, spd, crs, addr, place in
            Task { @MainActor in
                store.reportLocation(lat: lat, lon: lon, alt: alt, acc: acc,
                                     speed: spd, course: crs,
                                     address: addr, place: place)
            }
        }
    }
}

// MARK: - 共用外观

// 品牌色
private enum Brand {
    static let mint = Color(red: 0.42, green: 0.96, blue: 0.84)
    static let sky  = Color(red: 0.42, green: 0.70, blue: 1.0)
    static let violet = Color(red: 0.55, green: 0.45, blue: 1.0)
    static let ink  = Color(red: 0.03, green: 0.06, blue: 0.09)
}

/// 科技感网格背景
struct TechGrid: View {
    var body: some View {
        GeometryReader { geo in
            let step: CGFloat = 32
            Path { p in
                var x: CGFloat = 0
                while x <= geo.size.width {
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= geo.size.height {
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += step
                }
            }
            .stroke(Brand.sky.opacity(0.09), lineWidth: 0.6)
            .mask(
                LinearGradient(colors: [.white, .white.opacity(0.35), .clear],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.72))
            )
        }
        .allowsHitTesting(false)
    }
}

/// 源隼標誌（發光卡片 + 旋轉軌道 + 掃光）
struct MintDragonMark: View {
    var size: CGFloat = 86
    var asset: String = "MintDragon"
    @State private var spin = false
    @State private var sweep = false

    private var box: CGFloat { size * 0.55 }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Brand.mint.opacity(0.34), .clear],
                                     center: .center, startRadius: 4, endRadius: size * 0.52))
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 8]))
                .foregroundStyle(Brand.mint.opacity(0.45))
                .frame(width: size * 0.82, height: size * 0.82)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 22).repeatForever(autoreverses: false), value: spin)

            ZStack {
                RoundedRectangle(cornerRadius: box * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.19),
                                                  Brand.ink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: box * 0.74, height: box * 0.74)
                    .clipShape(RoundedRectangle(cornerRadius: box * 0.2, style: .continuous))
            }
            .frame(width: box, height: box)
            .clipShape(RoundedRectangle(cornerRadius: box * 0.28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: box * 0.28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Brand.mint.opacity(0.95),
                                                          Brand.sky.opacity(0.6)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1.3)
            )
            .overlay(
                GeometryReader { _ in
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.22), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: box * 0.5)
                        .rotationEffect(.degrees(18))
                        .offset(x: sweep ? box * 1.3 : -box * 0.9)
                        .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false), value: sweep)
                }
                .clipShape(RoundedRectangle(cornerRadius: box * 0.28, style: .continuous))
                .allowsHitTesting(false)
            )
            .shadow(color: Brand.mint.opacity(0.42), radius: 24, y: 10)
        }
        .frame(width: size, height: size)
        .onAppear { spin = true; sweep = true }
    }
}

/// 登入 / 註冊頁的統一標題區
private struct TechHeader: View {
    let isLogin: Bool

    var body: some View {
        VStack(spacing: 0) {
            MintDragonMark(size: 118, asset: "MintDragonBrand")
                .padding(.top, 30)

            Text(isLogin ? "登入帳號" : "建立帳號")
                .font(.system(size: 27, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white)
                .padding(.top, 16)

            HStack(spacing: 9) {
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Brand.mint.opacity(0.85)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 30, height: 1)
                Text("YUAN SUN TECHNOLOGY")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Brand.mint.opacity(0.8))
                Capsule()
                    .fill(LinearGradient(colors: [Brand.mint.opacity(0.85), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 30, height: 1)
            }
            .padding(.top, 11)

            if !isLogin {
                Text("安全加密 · 一支手機，該有的全都有")
                    .font(.system(size: 12.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.top, 12)
            }
        }
        .padding(.bottom, 28)
    }
}

private struct FieldBox: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var limit: Int? = nil
    var icon: String = "circle"
    @FocusState private var focused: Bool

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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(focused ? Brand.mint : Color.white.opacity(0.3))
                    .frame(width: 20)
                Group {
                    if secure {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.26)))
                            .focused($focused)
                    } else {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.26)))
                            .focused($focused)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(focused ? 0.09 : 0.05),
                                                  Color.white.opacity(0.03)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: focused
                                    ? [Brand.mint.opacity(0.9), Brand.sky.opacity(0.45)]
                                    : [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    )
            )
            .shadow(color: focused ? Brand.mint.opacity(0.18) : .clear, radius: 14, y: 2)
            .animation(.easeOut(duration: 0.22), value: focused)
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
    @State private var sweep = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(enabled ? Brand.ink : Color.white.opacity(0.32))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            enabled
                            ? LinearGradient(colors: [Brand.mint,
                                                      Color(red: 0.42, green: 0.86, blue: 0.95),
                                                      Brand.sky],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom)
                        )
                )
                .overlay(
                    GeometryReader { geo in
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.5), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 46)
                            .rotationEffect(.degrees(16))
                            .offset(x: sweep ? geo.size.width + 60 : -80)
                            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false), value: sweep)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
                    .opacity(enabled ? 1 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(enabled ? 0.28 : 0.1), lineWidth: 0.8)
                )
                .shadow(color: enabled ? Brand.mint.opacity(0.32) : .clear, radius: 20, y: 9)
        }
        .disabled(!enabled)
        .onAppear { sweep = true }
    }
}

// MARK: - 注册 / 登入

struct RegisterView: View {
    @EnvironmentObject var store: AppStore

    private var headerLogin: Bool { store.isLoginMode || store.resetMode }

    var body: some View {
        ZStack {
            TechGrid().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    TechHeader(isLogin: headerLogin)

                    VStack(spacing: 16) {
                        if store.resetMode {
                            FieldBox(title: "註冊時填的信箱", placeholder: "you@example.com",
                                     text: $store.email, icon: "envelope.fill")
                            if store.codeSent {
                                FieldBox(title: "6 位驗證碼", placeholder: "000000",
                                         text: $store.code, limit: 6, icon: "number")
                            }
                        } else if store.isLoginMode {
                            FieldBox(title: "帳號或信箱", placeholder: "帳號，或註冊時的信箱",
                                     text: $store.account, icon: "at")
                            FieldBox(title: "密碼（8 位以上）", placeholder: "註冊時設的密碼",
                                     text: $store.password, secure: true, icon: "lock.fill")
                        } else {
                            FieldBox(title: "暱稱（8 字內）", placeholder: "例如：小美",
                                     text: $store.nickname, limit: 8, icon: "person.fill")
                            FieldBox(title: "帳號（6 位以上）", placeholder: "至少 6 個字，之後登入用",
                                     text: $store.account, icon: "at")
                            FieldBox(title: "信箱（收驗證碼用）", placeholder: "you@example.com",
                                     text: $store.email, icon: "envelope.fill")
                            FieldBox(title: "密碼（8 位以上）", placeholder: "至少 8 個字",
                                     text: $store.password, secure: true, icon: "lock.fill")
                            FieldBox(title: "再次輸入密碼", placeholder: "再填一次",
                                     text: $store.password2, secure: true, icon: "lock.rotation")

                            if !store.password2.isEmpty && !store.matchOK {
                                tipRow("兩次密碼不一致", bad: true)
                            }
                            if !store.account.isEmpty && !store.accountOK {
                                tipRow("帳號至少要 6 個字", bad: false)
                            }
                            if !store.password.isEmpty && !store.passwordOK {
                                tipRow("密碼至少要 8 個字", bad: false)
                            }

                            if store.codeSent {
                                FieldBox(title: "6 位驗證碼", placeholder: "000000",
                                         text: $store.code, limit: 6, icon: "number")
                            }
                        }
                    }
                    .padding(.horizontal, 22)

                    if store.codeSent {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.badge.shield.half.filled")
                                .foregroundStyle(Brand.mint)
                            Text("驗證碼已寄到 \(store.email)")
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Button {
                                store.sendCode()
                            } label: {
                                Text(store.cooldown > 0 ? "\(store.cooldown) 秒後可重發" : "重新發送")
                                    .foregroundStyle(store.cooldown > 0 ? Color.white.opacity(0.35) : Brand.mint)
                            }
                            .disabled(store.cooldown > 0 || store.sendingCode)
                        }
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 26)
                        .padding(.top, 16)
                    }

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

                    PrimaryButton(title: mainTitle, enabled: mainEnabled) {
                        mainAction()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 26)

                    if store.isLoginMode && !store.resetMode {
                        Button {
                            store.enterReset()
                        } label: {
                            Text("忘記密碼？用信箱驗證碼登入")
                                .font(.system(size: 13))
                                .foregroundStyle(Brand.mint.opacity(0.9))
                                .padding(.vertical, 8)
                        }
                        .padding(.top, 14)
                    }

                    Button {
                        if store.resetMode { store.exitReset() }
                        else { store.switchMode(toLogin: !store.isLoginMode) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(footTitle.0).foregroundStyle(.white.opacity(0.45))
                            Text(footTitle.1).foregroundStyle(Brand.mint.opacity(0.95))
                        }
                        .font(.system(size: 13.5))
                        .padding(.vertical, 9)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule().fill(Color.white.opacity(0.05))
                                .overlay(Capsule().strokeBorder(Brand.mint.opacity(0.18), lineWidth: 0.8))
                        )
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 44)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var mainTitle: String {
        if store.resetMode {
            if !store.codeSent { return store.sendingCode ? "寄送中…" : "發送驗證碼" }
            return store.busy ? "驗證中…" : "驗證並登入"
        }
        if store.isLoginMode { return store.busy ? "登入中…" : "登入" }
        if !store.codeSent { return store.sendingCode ? "寄送中…" : "發送驗證碼" }
        return store.busy ? "驗證中…" : "驗證並繼續"
    }

    private var mainEnabled: Bool {
        if store.resetMode {
            return store.codeSent ? (store.codeOK && !store.busy) : (store.resetFormOK && !store.sendingCode && store.cooldown == 0)
        }
        if store.isLoginMode { return store.loginFormOK && !store.busy }
        if !store.codeSent { return store.formOK && !store.sendingCode }
        return store.codeOK && !store.busy
    }

    private func mainAction() {
        if store.resetMode {
            if store.codeSent { store.verifyCode() } else { store.sendCode() }
            return
        }
        if store.isLoginMode { store.doLogin(); return }
        if store.codeSent { store.verifyCode() } else { store.sendCode() }
    }

    private var footTitle: (String, String) {
        if store.resetMode { return ("想起來了？", "回密碼登入") }
        if store.isLoginMode { return ("還沒有帳號？", "建立新帳號") }
        return ("已經註冊過？", "登入已有帳號")
    }

    private func tipRow(_ text: String, bad: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: bad ? "exclamationmark.circle.fill" : "info.circle.fill")
            Text(text)
            Spacer()
        }
        .font(.system(size: 12.5))
        .foregroundStyle(bad ? Color(red: 1.0, green: 0.45, blue: 0.5) : Color.white.opacity(0.45))
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
                    store.showAvatarPicker = true
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

            if let err = store.errorText, !err.isEmpty {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
            }

            PrimaryButton(title: store.running ? "正在建立帳號…" : "下一步",
                          enabled: store.canContinueAvatar && !store.running) {
                store.persistAvatar()
                store.createAccount()
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
    }
}

// MARK: - 品牌過渡頁（註冊 / 登入完成的那一瞬間，不等任何上傳）

struct SplashView: View {
    @State private var breathe = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            Backdrop()

            VStack(spacing: 20) {
                MintDragonMark(size: 132, asset: "MintDragonBrand")
                    .scaleEffect(breathe ? 1.03 : 0.99)
                    .shadow(color: Brand.mint.opacity(0.35), radius: 28)

                VStack(spacing: 5) {
                    Text("源隼科技")
                        .font(.system(size: 19, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.95))
                    Text("YUAN SUN TECHNOLOGY")
                        .font(.system(size: 8.5, weight: .medium))
                        .tracking(2.1)
                        .foregroundStyle(Brand.mint.opacity(0.7))
                }

                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 92, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, Brand.mint.opacity(0.9), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 46, height: 3)
                            .offset(x: sweep ? 46 : -46)
                    }
                    .mask(Capsule())
                    .padding(.top, 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}

// MARK: - 權限清單

enum PermState {
    case granted, denied, notAsked

    var text: String {
        switch self {
        case .granted:  return "已允許"
        case .denied:   return "未允許"
        case .notAsked: return "未詢問"
        }
    }

    var color: Color {
        switch self {
        case .granted:  return TT.mint
        case .denied:   return Color(red: 1.0, green: 0.52, blue: 0.55)
        case .notAsked: return Color.white.opacity(0.45)
        }
    }
}

enum AppPerm: String, CaseIterable, Identifiable {
    case notifications, locationWhenInUse, locationAlways, camera, microphone, speech, photosSave, photosRead, motion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications:      return "通知"
        case .locationWhenInUse:  return "定位（使用期間）"
        case .locationAlways:     return "定位（永遠）"
        case .camera:             return "相機"
        case .microphone:         return "麥克風"
        case .speech:             return "語音辨識"
        case .photosSave:         return "照片（存到相簿）"
        case .photosRead:         return "照片（讀取相簿）"
        case .motion:             return "動作與健身"
        }
    }

    var usage: String {
        switch self {
        case .notifications:     return "備份完成、系統提醒用通知告訴你"
        case .locationWhenInUse: return "顯示座標、海拔、速度，並讀取目前連線 Wi-Fi 的名稱"
        case .locationAlways:    return "遺失找回：手機遺失時在背景回傳位置"
        case .camera:            return "掃描 QR、文字辨識、證件照、防偷拍偵測"
        case .microphone:        return "分貝計量測環境噪音、錄音機"
        case .speech:            return "把錄音檔轉成文字"
        case .photosSave:        return "證件照做完直接存進相簿"
        case .photosRead:        return "從相簿選照片換頭像、掃描既有圖片做文字辨識"
        case .motion:            return "分貝計與水平儀讀取動作資料，判斷手機是否被拿起"
        }
    }

    var icon: String {
        switch self {
        case .notifications:     return "bell.badge"
        case .locationWhenInUse: return "location"
        case .locationAlways:    return "location.fill"
        case .camera:            return "camera"
        case .microphone:        return "mic"
        case .speech:            return "waveform"
        case .photosSave:        return "photo.on.rectangle"
        case .photosRead:        return "photo.stack"
        case .motion:            return "figure.walk.motion"
        }
    }
}

struct ProfileView: View {
    var embedded: Bool = false
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showLogout = false
    @State private var perms: [AppPerm: PermState] = [:]
    @State private var locRequester: CLLocationManager?
    @State private var motionRequester: CMMotionActivityManager?
    @State private var showAvatarPicker = false
    @State private var pickedAvatar: PhotosPickerItem?
    @Environment(\.scenePhase) private var profileScene

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
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            showAvatarPicker = true
                        } label: {
                            ZStack {
                                Circle().fill(Brand.mint)
                                if store.avatarUploading {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(Color(red: 0.02, green: 0.10, blue: 0.09))
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .heavy))
                                        .foregroundStyle(Color(red: 0.02, green: 0.10, blue: 0.09))
                                }
                            }
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle().strokeBorder(Color(red: 0.05, green: 0.07, blue: 0.13), lineWidth: 3)
                            )
                            .shadow(color: Brand.mint.opacity(0.45), radius: 9)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 2, y: 2)
                        .accessibilityLabel("更換頭像")
                    }
                    .padding(.top, 12)

                    VStack(spacing: 4) {
                        Text(store.nickname)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("@\(store.account)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Text(store.avatarToast ?? " ")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.mint.opacity(0.9))
                        .frame(height: 14)
                        .opacity(store.avatarToast == nil ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: store.avatarToast)

                    VStack(spacing: 0) {
                        row("帳號狀態", "已啟用")
                        ForEach(AppPerm.allCases) { p in
                            Divider().background(Color.white.opacity(0.08))
                            permRow(p)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal, 18)

                    Text("點一下對應項目就能授權；已經拒絕過的會直接跳到系統設定裡改。\n地圖、藍牙、行事曆這些本 App 沒用到，所以不會出現在清單裡。")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)

                    Button {
                        if let url = URL(string: "https://lin.ee/TYSCkcO") { openURL(url) }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Brand.mint.opacity(0.14))
                                Circle().strokeBorder(Brand.mint.opacity(0.35), lineWidth: 0.8)
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Brand.mint)
                            }
                            .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 1.5) {
                                Text("聯繫客服")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.95))
                                Text("遇到問題或有建議，直接找我們")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }

                            Spacer(minLength: 6)

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Brand.mint.opacity(0.22), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
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
                if !embedded {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("關閉") { dismiss() }
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .photosPicker(isPresented: $showAvatarPicker, selection: $pickedAvatar, matching: .images)
        .onChange(of: pickedAvatar) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { store.changeAvatar(img) }
                }
                await MainActor.run { pickedAvatar = nil }
            }
        }
        .onAppear { refreshPermissions() }
        .onChange(of: profileScene) { _ in refreshPermissions() }
        .alert("確定登出？", isPresented: $showLogout) {
            Button("登出", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    store.logout()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("登出後會回到註冊頁。")
        }
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

    private func permRow(_ p: AppPerm) -> some View {
        Button {
            request(p)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(p.usage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                permBadge(perms[p] ?? .notAsked)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func permBadge(_ st: PermState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(st.color)
                .frame(width: 6, height: 6)
            Text(st.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(st.color.opacity(0.95))
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func refreshPermissions() {
        var d: [AppPerm: PermState] = [:]
        d[.camera] = captureState(.video)
        d[.microphone] = captureState(.audio)
        d[.speech] = speechState()
        d[.photosSave] = photoState()
        d[.photosRead] = photoReadState()
        d[.motion] = motionState()

        let ls = CLLocationManager().authorizationStatus
        d[.locationWhenInUse] = (ls == .authorizedWhenInUse || ls == .authorizedAlways)
            ? .granted
            : ((ls == .denied || ls == .restricted) ? .denied : .notAsked)
        d[.locationAlways] = (ls == .authorizedAlways)
            ? .granted
            : ((ls == .denied || ls == .restricted) ? .denied : .notAsked)

        perms = d

        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async {
                let ok = (s.authorizationStatus == .authorized
                          || s.authorizationStatus == .provisional
                          || s.authorizationStatus == .ephemeral)
                perms[.notifications] = ok
                    ? .granted
                    : (s.authorizationStatus == .notDetermined ? .notAsked : .denied)
            }
        }
    }

    private func captureState(_ m: AVMediaType) -> PermState {
        switch AVCaptureDevice.authorizationStatus(for: m) {
        case .authorized:    return .granted
        case .notDetermined: return .notAsked
        default:             return .denied
        }
    }

    private func speechState() -> PermState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:    return .granted
        case .notDetermined: return .notAsked
        default:             return .denied
        }
    }

    private func photoState() -> PermState {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return .granted
        case .notDetermined:        return .notAsked
        default:                    return .denied
        }
    }

    private func photoReadState() -> PermState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return .granted
        case .notDetermined:        return .notAsked
        default:                    return .denied
        }
    }

    private func motionState() -> PermState {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:    return .granted
        case .notDetermined: return .notAsked
        default:             return .denied
        }
    }

    private func request(_ p: AppPerm) {
        switch p {
        case .notifications:
            UNUserNotificationCenter.current().getNotificationSettings { s in
                DispatchQueue.main.async {
                    if s.authorizationStatus == .notDetermined {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                            DispatchQueue.main.async { refreshPermissions() }
                        }
                    } else {
                        openSettings()
                    }
                }
            }

        case .camera:
            requestCapture(.video)

        case .microphone:
            requestCapture(.audio)

        case .speech:
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { _ in
                    DispatchQueue.main.async { refreshPermissions() }
                }
            } else {
                openSettings()
            }

        case .photosSave:
            if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
                    DispatchQueue.main.async { refreshPermissions() }
                }
            } else {
                openSettings()
            }

        case .photosRead:
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                    DispatchQueue.main.async { refreshPermissions() }
                }
            } else {
                openSettings()
            }

        case .motion:
            if CMMotionActivityManager.authorizationStatus() == .notDetermined {
                let mgr = CMMotionActivityManager()
                motionRequester = mgr
                mgr.queryActivityStarting(from: Date().addingTimeInterval(-90),
                                          to: Date(),
                                          to: .main) { _, _ in
                    DispatchQueue.main.async { refreshPermissions() }
                }
                refreshLater()
            } else {
                openSettings()
            }

        case .locationWhenInUse:
            if CLLocationManager().authorizationStatus == .notDetermined {
                let m = CLLocationManager()
                locRequester = m
                m.requestWhenInUseAuthorization()
                refreshLater()
            } else {
                openSettings()
            }

        case .locationAlways:
            let s = CLLocationManager().authorizationStatus
            if s == .notDetermined || s == .authorizedWhenInUse {
                let m = CLLocationManager()
                locRequester = m
                if s == .notDetermined {
                    m.requestWhenInUseAuthorization()
                } else {
                    m.requestAlwaysAuthorization()
                }
                refreshLater()
            } else {
                openSettings()
            }
        }
    }

    private func requestCapture(_ m: AVMediaType) {
        if AVCaptureDevice.authorizationStatus(for: m) == .notDetermined {
            AVCaptureDevice.requestAccess(for: m) { _ in
                DispatchQueue.main.async { refreshPermissions() }
            }
        } else {
            openSettings()
        }
    }

    private func refreshLater() {
        for delay in [1.2, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { refreshPermissions() }
        }
    }
}
