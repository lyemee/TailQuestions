import AppKit
import SwiftUI

/// Claude 창 오른쪽에 붙어 다니는 꼬리질문 패널.
@MainActor
final class PanelController {
    private let panel: NSPanel
    private let model: AppModel
    private var timer: Timer?

    init(model: AppModel) {
        self.model = model
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "꼬리질문"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 300, height: 400)
        panel.contentView = NSHostingView(rootView: PanelRootView().environmentObject(model))
        panel.center()
    }

    var isKeyAndVisible: Bool { panel.isVisible && panel.isKeyWindow }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        dock()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func hide() {
        panel.orderOut(nil)
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if !panel.isVisible {
            timer?.invalidate()
            timer = nil
            return
        }
        dock()
    }

    /// Claude 창 오른쪽에 붙인다. 화면 밖으로 나가면 Claude 창 오른쪽 가장자리 안쪽에 겹쳐 둔다.
    private func dock() {
        guard model.docked, let claude = AXReader.claudeApp(),
              let f = AXReader.mainWindowFrame(pid: claude.processIdentifier) else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? f
        let width = panel.frame.width

        var target = NSRect(x: f.maxX + 4, y: f.minY, width: width, height: f.height)
        if target.maxX > visible.maxX {
            target.origin.x = min(f.maxX, visible.maxX) - width
        }
        let current = panel.frame
        if abs(current.minX - target.minX) > 1 || abs(current.minY - target.minY) > 1
            || abs(current.height - target.height) > 1 {
            panel.setFrame(target, display: true)
        }
    }
}

/// 비활성 상태에서도 키 입력을 받을 수 있는 패널.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
