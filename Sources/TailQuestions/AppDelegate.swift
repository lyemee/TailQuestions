import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(model: model)
        setupStatusItem()

        // ⌥⇧Space: 선택한 텍스트로 꼬리질문 시작 / 패널 토글
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), id: 1) { [weak self] in
            Task { @MainActor in await self?.handleHotKey() }
        }

        let trusted = AXReader.isTrusted(prompt: true)
        DebugLog.log("launch: trusted=\(trusted) claudeCode=\(ClaudeCodeClient.binaryPath ?? "없음") backend=\(model.backend.rawValue)")
        if let claude = AXReader.claudeApp() {
            AXReader.enableWebAccessibility(pid: claude.processIdentifier)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let isClaude = app.bundleIdentifier == AXReader.claudeBundleID
            let isSelf = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                if isClaude {
                    self?.panel.claudeActivated()      // Claude로 돌아오면 바로 같이 올라옴
                } else if !isSelf {
                    self?.panel.otherAppActivated()    // 다른 앱이면 바로 Claude와 함께 뒤로
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == AXReader.claudeBundleID else { return }
            let pid = app.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { AXReader.enableWebAccessibility(pid: pid) }
        }

        // 앱 위치가 바뀌었을 수 있으니 자동 실행을 켜 둔 경우 현재 위치로 다시 등록
        if model.launchAtLogin { model.setLaunchAtLogin(true) }

        model.refreshConversation = { [weak self] in
            guard let self, let claude = AXReader.claudeApp() else { return }
            if let conv = await self.readConversation(pid: claude.processIdentifier) {
                self.model.conversation = conv
            }
        }

        panel.show()   // 메뉴바 앱이라 실행해도 티가 안 나서, 처음엔 패널을 띄워 둔다
    }

    private func readConversation(pid: pid_t) async -> Conversation? {
        let setResult = AXReader.enableWebAccessibility(pid: pid)
        // 접근성 트리가 막 켜진 경우 만들어질 때까지 잠깐씩 기다리며 다시 시도
        for attempt in 0..<6 {
            if let conv = AXReader.readConversation(pid: pid) {
                if attempt > 0 { DebugLog.log("readConversation: \(attempt)번 재시도 후 성공") }
                return conv
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        DebugLog.log("readConversation 실패 (AXManualAccessibility=\(setResult.rawValue)). 화면 구조:\n"
                     + AXReader.structureSummary(pid: pid))
        return nil
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: "꼬리질문")

        let menu = NSMenu()
        menu.addItem(withTitle: "패널 열기  (⌥⇧Space)", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openPanel() { panel.show() }

    @objc private func openSettings() {
        model.showSettings = true
        panel.show()
    }

    private func handleHotKey() async {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isSelf = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier

        // 패널을 보고 있을 때 다시 누르면 닫는다.
        if isSelf {
            if panel.isKeyAndVisible { panel.hide() } else { panel.show() }
            return
        }

        let isClaude = frontmost?.bundleIdentifier == AXReader.claudeBundleID
        if isClaude, let pid = frontmost?.processIdentifier {
            AXReader.enableWebAccessibility(pid: pid)
        }

        let trusted = AXReader.isTrusted(prompt: false)
        var selection = AXReader.selectedTextViaAX()
        let viaAX = selection != nil
        if selection == nil, trusted {
            selection = await AXReader.selectedTextViaCopy()
        }

        var conversation: Conversation?
        if isClaude, let pid = frontmost?.processIdentifier {
            conversation = await readConversation(pid: pid)
        }

        let kinds = Dictionary(grouping: conversation?.blocks ?? [], by: \.kind.rawValue).mapValues(\.count)
        DebugLog.log("hotkey: front=\(frontmost?.bundleIdentifier ?? "nil") trusted=\(trusted) "
            + "selection=\(selection?.count ?? 0)자(\(viaAX ? "AX" : "copy")) blocks=\(kinds)")

        model.showSettings = false
        if let selection {
            // 드래그한 부분에서 새 가지
            model.startThread(selection: selection, conversation: conversation)
        } else {
            // 선택 없이 누르면 main 대화와 가지 목록
            if let conversation { model.conversation = conversation }
            model.select(nil)
        }
        panel.show()
    }
}
