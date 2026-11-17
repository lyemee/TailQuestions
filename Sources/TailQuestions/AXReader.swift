import AppKit
import ApplicationServices

/// macOS 손쉬운 사용(Accessibility) API로 Claude 데스크톱 앱의 화면 내용을 읽는다.
enum AXReader {
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    // MARK: 권한

    @discardableResult
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func claudeApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).first
    }

    /// Electron 앱은 기본적으로 웹 콘텐츠의 접근성 트리를 숨긴다. 이 속성을 켜야 대화 내용이 보인다.
    static func enableWebAccessibility(pid: pid_t) {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: 헬퍼

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func role(_ el: AXUIElement) -> String {
        (attr(el, kAXRoleAttribute) as? String) ?? ""
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    // MARK: 선택한 텍스트

    static func selectedTextViaAX() -> String? {
        let sys = AXUIElementCreateSystemWide()
        guard let focused = element(sys, kAXFocusedUIElementAttribute) else { return nil }
        if let s = attr(focused, kAXSelectedTextAttribute) as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return nil
    }

    /// AX로 못 읽을 때: ⌘C를 보내 클립보드로 읽은 뒤 원래 클립보드를 되돌려 놓는다.
    @MainActor
    static func selectedTextViaCopy() async -> String? {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { dict[t] = d } }
            return dict
        }
        let before = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)   // 'c'
        let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pb.changeCount != before { break }
        }
        guard pb.changeCount != before else { return nil }
        let text = pb.string(forType: .string)

        pb.clearContents()
        let items = saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in dict { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    // MARK: 창 위치

    private static func mainWindow(pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        if let w = element(appEl, kAXFocusedWindowAttribute) { return w }
        if let w = element(appEl, kAXMainWindowAttribute) { return w }
        return ((attr(appEl, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first
    }

    /// Claude 창의 위치를 Cocoa 좌표(왼쪽 아래 원점)로 돌려준다.
    static func mainWindowFrame(pid: pid_t) -> NSRect? {
        guard let w = mainWindow(pid: pid), let f = frame(w), f.width > 100 else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: f.minX, y: primaryHeight - f.minY - f.height, width: f.width, height: f.height)
    }

    // MARK: 대화 읽기

    /// claude.ai 웹 UI에서 메시지를 감싸는 요소의 CSS 클래스 단서.
    private static func blockKind(of el: AXUIElement) -> TranscriptBlock.Kind? {
        guard let classes = attr(el, "AXDOMClassList") as? [String], !classes.isEmpty else { return nil }
        let joined = classes.joined(separator: " ")
        if joined.contains("font-user-message") { return .user }
        if joined.contains("font-claude-response") || joined.contains("font-claude-message") { return .assistant }
        return nil
    }

    private struct Leaf { var text: String; var top: CGFloat? }

    private static func collectText(_ el: AXUIElement, into leaves: inout [Leaf], budget: inout Int) {
        guard budget > 0 else { return }
        budget -= 1
        if role(el) == kAXStaticTextRole as String {
            if let v = attr(el, kAXValueAttribute) as? String, !v.isEmpty {
                leaves.append(Leaf(text: v, top: frame(el)?.minY))
            }
            return
        }
        for c in children(el) { collectText(c, into: &leaves, budget: &budget) }
    }

    /// 같은 줄에 있는 조각은 이어 붙이고, 줄이 바뀌면 줄바꿈을 넣는다.
    private static func join(_ leaves: [Leaf]) -> String {
        var out = ""
        var lastTop: CGFloat?
        for leaf in leaves {
            if let lt = lastTop, let t = leaf.top, abs(t - lt) > 4 { out += "\n" }
            out += leaf.text
            lastTop = leaf.top ?? lastTop
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func findMessages(_ el: AXUIElement, into blocks: inout [TranscriptBlock], budget: inout Int) {
        guard budget > 0 else { return }
        budget -= 1
        if let kind = blockKind(of: el) {
            var leaves: [Leaf] = []
            collectText(el, into: &leaves, budget: &budget)
            let text = join(leaves)
            if !text.isEmpty { blocks.append(TranscriptBlock(kind: kind, text: text)) }
            return
        }
        for c in children(el) { findMessages(c, into: &blocks, budget: &budget) }
    }

    private static func findWebArea(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if role(el) == "AXWebArea" { return el }
        guard depth < 30 else { return nil }
        for c in children(el) {
            if let found = findWebArea(c, depth: depth + 1) { return found }
        }
        return nil
    }

    static func readConversation(pid: pid_t) -> Conversation? {
        guard let window = mainWindow(pid: pid) else { return nil }
        let title = (attr(window, kAXTitleAttribute) as? String) ?? "Claude"
        guard let web = findWebArea(window) else { return nil }

        var blocks: [TranscriptBlock] = []
        var budget = 60_000
        findMessages(web, into: &blocks, budget: &budget)

        // 메시지 구분 단서를 못 찾으면 화면 전체 텍스트를 한 덩어리로 보낸다.
        if blocks.isEmpty {
            var leaves: [Leaf] = []
            var b = 60_000
            collectText(web, into: &leaves, budget: &b)
            let text = join(leaves)
            guard !text.isEmpty else { return nil }
            blocks = [TranscriptBlock(kind: .unknown, text: text)]
        }
        return Conversation(title: title, blocks: blocks)
    }
}
