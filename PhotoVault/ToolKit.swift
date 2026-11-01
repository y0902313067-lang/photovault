import SwiftUI
import UIKit

// MARK: - 工具模組配色

enum TT {
    static let mint   = Color(red: 0.42, green: 0.96, blue: 0.84)
    static let teal   = Color(red: 0.36, green: 0.86, blue: 0.86)
    static let blue   = Color(red: 0.42, green: 0.70, blue: 1.00)
    static let indigo = Color(red: 0.44, green: 0.42, blue: 1.00)
    static let violet = Color(red: 0.66, green: 0.42, blue: 1.00)
    static let amber  = Color(red: 1.00, green: 0.76, blue: 0.38)
    static let rose   = Color(red: 1.00, green: 0.44, blue: 0.52)
    static let ink    = Color(red: 0.035, green: 0.045, blue: 0.070)
    static let lime   = Color(red: 0.62, green: 0.98, blue: 0.52)

    static let ramp = LinearGradient(colors: [mint, teal, blue, indigo],
                                     startPoint: .leading, endPoint: .trailing)
}

// MARK: - 面板

struct TTPanel<Content: View>: View {
    var accent: Color = TT.mint
    var padding: CGFloat = 16
    private let content: Content

    init(accent: Color = TT.mint, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [accent.opacity(0.32),
                                                Color.white.opacity(0.06),
                                                Color.white.opacity(0.03)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
    }
}

// MARK: - 區塊標題

struct TTSectionTitle: View {
    let text: String
    var accent: Color = TT.mint

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3, height: 12)
                .shadow(color: accent.opacity(0.7), radius: 5)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.62))
            Rectangle()
                .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }
}

// MARK: - 數值格

struct TTStat: View {
    let title: String
    let value: String
    var unit: String = ""
    var accent: Color = TT.mint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.34))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(accent.opacity(0.75))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - 鍵值列

struct TTKeyRow: View {
    let key: String
    let value: String
    var accent: Color = TT.mint
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12.5, weight: .medium,
                              design: mono ? .monospaced : .default))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }
}

// MARK: - 小膠囊

struct TTPill: View {
    let text: String
    var color: Color = TT.mint
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(filled ? TT.ink : color.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5.5)
        .background(
            Capsule().fill(filled ? color.opacity(0.9) : color.opacity(0.10))
        )
        .overlay(Capsule().strokeBorder(color.opacity(filled ? 0 : 0.28), lineWidth: 1))
    }
}

// MARK: - 橫向量條

struct TTMeterBar: View {
    let ratio: Double
    var accent: Color = TT.mint
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.55), accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geo.size.width * CGFloat(min(max(ratio, 0), 1))))
                    .shadow(color: accent.opacity(0.5), radius: 6)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 主按鈕

struct TTButton: View {
    let title: String
    var icon: String? = nil
    var accent: Color = TT.mint
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 14.5, weight: .semibold))
            }
            .foregroundStyle(enabled ? TT.ink : Color.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled
                          ? LinearGradient(colors: [accent, TT.blue],
                                           startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color.white.opacity(0.07),
                                                    Color.white.opacity(0.05)],
                                           startPoint: .leading, endPoint: .trailing))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - 頁面骨架

struct TTScreen<Content: View>: View {
    let title: String
    let subtitle: String
    var badge: String? = nil
    var badgeOn: Bool = false
    var accent: Color = TT.mint
    @Environment(\.dismiss) private var dismiss
    private let content: Content

    init(title: String,
         subtitle: String,
         badge: String? = nil,
         badgeOn: Bool = false,
         accent: Color = TT.mint,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.badgeOn = badgeOn
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        ZStack {
            Backdrop()
            TechGrid()

            VStack(spacing: 0) {
                TTPageHeader(title: title,
                             subtitle: subtitle,
                             badge: badge,
                             badgeOn: badgeOn,
                             accent: accent) { dismiss() }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) { content }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 34)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .keyboardDismissBar(accent: accent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - 鍵盤收起

/// 收起目前正在編輯的輸入框，鍵盤會跟著退場
enum KeyboardDismiss {
    static func now() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// 在鍵盤上方浮出一顆「收起鍵盤」，任何有輸入框的頁面掛上就有
struct KeyboardDismissBar: ViewModifier {
    var accent: Color = TT.mint

    @State private var overlap: CGFloat = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if shown {
                    Button {
                        KeyboardDismiss.now()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 13, weight: .semibold))
                            Text("收起鍵盤")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 15)
                        .frame(height: 36)
                        .background(Capsule().fill(TT.ink.opacity(0.94)))
                        .overlay(Capsule().strokeBorder(accent.opacity(0.38), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, overlap + 10)
                    .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let screen = UIScreen.main.bounds
                let height = max(0, screen.maxY - frame.minY)
                animate(note) {
                    overlap = height
                    shown = height > 90
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
                animate(note) {
                    overlap = 0
                    shown = false
                }
            }
    }

    private func animate(_ note: Notification, _ changes: @escaping () -> Void) {
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.22
        withAnimation(.easeOut(duration: duration)) { changes() }
    }
}

extension View {
    func keyboardDismissBar(accent: Color = TT.mint) -> some View {
        modifier(KeyboardDismissBar(accent: accent))
    }
}

struct TTPageHeader: View {
    let title: String
    let subtitle: String
    var badge: String? = nil
    var badgeOn: Bool = false
    var accent: Color = TT.mint
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(subtitle)
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.7)
                    .foregroundStyle(accent.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let badge = badge {
                TTPill(text: badge, color: badgeOn ? accent : Color.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - 動態掃光

struct TTSweep: View {
    var accent: Color = TT.mint
    @State private var go = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [accent.opacity(0.0),
                                              accent.opacity(0.22),
                                              accent.opacity(0.0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * 0.45)
                .offset(x: go ? geo.size.width : -geo.size.width * 0.5)
                .onAppear {
                    withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                        go = true
                    }
                }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - 環形數值

struct TTRing: View {
    let progress: Double
    var accent: Color = TT.mint
    var lineWidth: CGFloat = 8
    var track: Color = Color.white.opacity(0.08)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(
                    AngularGradient(colors: [accent.opacity(0.55), accent, TT.blue],
                                    center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.5), radius: 7)
        }
    }
}

// MARK: - 空狀態

struct TTEmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.22))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

// MARK: - 工具卡片（首頁 / 更多工具共用）

struct ToolCard: View {
    let tool: ToolRoute
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(colors: [tool.accent.opacity(0.9),
                                                        tool.accent.opacity(0.45)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            )
                            .frame(width: 38, height: 38)
                            .shadow(color: tool.accent.opacity(0.35), radius: 10, y: 4)
                        Image(systemName: tool.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TT.ink)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.16))
                        .padding(.top, 3)
                }

                Spacer(minLength: 10)

                Text(tool.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(tool.subtitle)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.22))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(13)
            .frame(height: 112)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [tool.accent.opacity(0.22),
                                                Color.white.opacity(0.05)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
