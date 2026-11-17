import AppKit
import SwiftUI

/// 아이콘과 같은 톤: 인디고(main 줄기) + 주황(가지), 따뜻한 무채색 배경.
enum Theme {
    static let bg = dynamic(light: 0xF7F6F2, dark: 0x1E1D1C)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x2A2927)
    static let sunken = dynamic(light: 0xEFEDE7, dark: 0x252422)
    static let border = dynamic(light: 0xE3E0D8, dark: 0x3A3836)
    static let text = dynamic(light: 0x1F1E1C, dark: 0xEDEBE6)
    static let secondary = dynamic(light: 0x6E6C66, dark: 0xA19E97)
    static let tertiary = dynamic(light: 0xA3A09A, dark: 0x6E6C66)

    static let main = dynamic(light: 0x5563F0, dark: 0x8A95FF)
    static let mainSoft = dynamic(light: 0xECEEFF, dark: 0x2D3060)
    static let branch = dynamic(light: 0xE8930C, dark: 0xF5A524)
    static let branchSoft = dynamic(light: 0xFFF3E0, dark: 0x3A2C17)
    static let success = dynamic(light: 0x2E9E5B, dark: 0x4CC27E)
    static let warning = dynamic(light: 0xC77700, dark: 0xF5A524)
    static let danger = dynamic(light: 0xD14343, dark: 0xF07070)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(isDark ? dark : light)
        })
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// 작은 아이콘 버튼 (헤더용)
struct IconButton: View {
    let systemName: String
    var active = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Theme.main : Theme.secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.sunken : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 앱 아이콘 (번들 밖에서 실행한 스크린샷 모드에서는 Resources/icon.png)
enum AppIcon {
    static var image: NSImage {
        if Bundle.main.bundleURL.pathExtension == "app" { return NSApp.applicationIconImage }
        return NSImage(contentsOfFile: "Resources/icon.png") ?? NSApp.applicationIconImage
    }
}

/// 둥근 기본 버튼
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        PillLabel(configuration: configuration, prominent: prominent)
    }
}

private struct PillLabel: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Color.white : Theme.text)
            .background(
                Capsule().fill(prominent ? Theme.main : Theme.sunken)
            )
            .overlay(Capsule().stroke(prominent ? Color.clear : Theme.border))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
    }
}
