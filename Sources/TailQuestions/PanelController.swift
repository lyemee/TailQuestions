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
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // 빈 툴바로 타이틀바를 키워서 신호등 버튼과 헤더가 한 줄에 오게 한다
        panel.toolbar = NSToolbar(identifier: "TailQuestionsToolbar")
        panel.toolbarStyle = .unifiedCompact
        panel.isMovableByWindowBackground = true
        // 항상 위에 뜨는 창이 아니라 일반 창. Claude 창 바로 위에 붙여서 같은 높이로 움직인다.
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // 모든 데스크탑에 고정하지 않고, 다시 보여줄 때 현재 데스크탑으로 옮겨 온다.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 420)
        panel.contentView = NSHostingView(rootView: PanelRootView().environmentObject(model))
        panel.center()

        // 닫기 버튼으로 닫으면 Claude가 다시 보여도 자동으로 열지 않는다.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wantsVisible = false }
        }
    }

    var isKeyAndVisible: Bool { panel.isVisible && panel.isKeyWindow }

    /// 사용자가 패널을 열어 둔 상태인지. (Claude가 안 보여서 잠시 숨긴 경우에도 true)
    private var wantsVisible = false

    func show() {
        wantsVisible = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        dock()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func hide() {
        wantsVisible = false
        panel.orderOut(nil)
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard wantsVisible else {
            timer?.invalidate()
            timer = nil
            return
        }
        // Claude 창이 지금 데스크탑에 보일 때만 패널을 보여준다.
        // (다른 데스크탑으로 이동, Claude 최소화·숨김 → 패널도 숨김. Claude가 안 켜져 있으면 그냥 보여줌)
        guard let claude = AXReader.claudeApp() else {
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        guard let claudeWindow = AXReader.frontWindowNumber(pid: claude.processIdentifier) else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        stickAbove(claudeWindow)
        dock()
    }

    /// Claude(또는 이 패널)를 쓰는 중이면 패널을 Claude보다 항상 위(floating)에 둬서
    /// Claude 창을 클릭해도 패널이 가려졌다 나타나는 깜빡임이 없게 한다.
    /// 다른 앱으로 넘어가면 일반 창으로 내려 Claude 바로 위 순서에 둔다 → 그 앱에 Claude와 함께 가려진다.
    private func stickAbove(_ claudeWindow: Int) {
        let front = NSWorkspace.shared.frontmostApplication
        let claudeOrSelfFront = front?.bundleIdentifier == AXReader.claudeBundleID
            || front?.processIdentifier == ProcessInfo.processInfo.processIdentifier

        if claudeOrSelfFront {
            if panel.level != .floating { panel.level = .floating }
            return
        }

        if panel.level != .normal { panel.level = .normal }
        let order = AXReader.onScreenWindows().map(\.number)
        guard let panelIndex = order.firstIndex(of: panel.windowNumber),
              let claudeIndex = order.firstIndex(of: claudeWindow) else {
            panel.order(.above, relativeTo: claudeWindow)
            return
        }
        // 패널이 Claude보다 뒤에 있을 때만 순서를 고친다 (불필요한 재정렬 = 깜빡임 방지)
        if panelIndex > claudeIndex {
            panel.order(.above, relativeTo: claudeWindow)
        }
    }

    /// 다른 앱이 앞으로 오면 즉시 일반 창으로 내린다.
    func otherAppActivated() {
        guard wantsVisible, panel.isVisible, let claude = AXReader.claudeApp(),
              let claudeWindow = AXReader.frontWindowNumber(pid: claude.processIdentifier) else { return }
        stickAbove(claudeWindow)
    }

    /// Claude가 앞으로 나오는 순간 바로 따라 올라오게 (타이머를 기다리지 않고).
    func claudeActivated() {
        guard wantsVisible else { return }
        tick()
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
