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
    @discardableResult
    static func enableWebAccessibility(pid: pid_t) -> AXError {
        let appEl = AXUIElementCreateApplication(pid)
        return AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// 진단용: 창의 접근성 구조(역할·CSS 클래스·자식 수)만 기록한다. 텍스트 내용은 남기지 않는다.
    static func structureSummary(pid: pid_t, maxNodes: Int = 250) -> String {
        guard let window = mainWindow(pid: pid) else { return "(창을 찾지 못함)" }
        var lines: [String] = []
        var count = 0
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard count < maxNodes, depth < 40 else { return }
            count += 1
            let kids = children(el)
            var line = String(repeating: " ", count: depth) + role(el)
            if let classes = attr(el, "AXDOMClassList") as? [String], !classes.isEmpty {
                line += " ." + classes.prefix(4).map { String($0.prefix(30)) }.joined(separator: ".")
            }
            if !kids.isEmpty { line += " (\(kids.count))" }
            lines.append(line)
            for k in kids { walk(k, depth + 1) }
        }
        walk(window, 0)
        return lines.joined(separator: "\n")
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

    /// 지금 보고 있는 데스크탑(Space)에 이 앱의 일반 창이 화면에 떠 있는지.
    /// 최소화·숨김 상태이거나 다른 데스크탑에 있으면 false. (화면 기록 권한 없이도 동작)
    static func hasVisibleWindow(pid: pid_t) -> Bool {
        frontWindowNumber(pid: pid) != nil
    }

    /// 지금 데스크탑에 보이는 이 앱의 가장 앞쪽 일반 창 번호. (창 목록은 앞→뒤 순서)
    static func frontWindowNumber(pid: pid_t) -> Int? {
        onScreenWindows().first { $0.pid == pid && $0.isNormal }?.number
    }

    struct WindowInfo { var number: Int; var pid: pid_t; var isNormal: Bool }

    /// 화면에 보이는 창 목록 (앞→뒤 순서). 화면 기록 권한 없이도 번호·소유 앱·크기는 읽을 수 있다.
    static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            var normal = false
            if (info[kCGWindowLayer as String] as? Int) == 0,
               let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: boundsDict) {
                normal = bounds.width > 200 && bounds.height > 200
            }
            return WindowInfo(number: number, pid: pid, isNormal: normal)
        }
    }

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

    private static func classes(_ el: AXUIElement) -> [String] {
        (attr(el, "AXDOMClassList") as? [String]) ?? []
    }

    /// 이 요소와 그 아래 몇 단계의 CSS 클래스로 내 질문/Claude 답변을 구분한다.
    private static func classifyByClasses(_ el: AXUIElement) -> TranscriptBlock.Kind? {
        var found: TranscriptBlock.Kind?
        func visit(_ e: AXUIElement, _ depth: Int) {
            guard found == nil, depth <= 5 else { return }
            let joined = classes(e).joined(separator: " ").lowercased()
            if joined.contains("user-message") || joined.contains("font-user") || joined.contains("message-user") {
                found = .user; return
            }
            if joined.contains("claude-response") || joined.contains("font-claude") || joined.contains("assistant") {
                found = .assistant; return
            }
            for c in children(e) { visit(c, depth + 1) }
        }
        visit(el, 0)
        return found
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
        // 화면 낭독기 전용 숨김 텍스트(sr-only)는 건너뛴다
        if classes(el).contains("sr-only") { return }
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

    /// 메시지 한 줄(`message-row`)을 감싸는 요소들을 찾는다.
    private static func findMessageRows(_ el: AXUIElement, into rows: inout [AXUIElement], budget: inout Int) {
        guard budget > 0 else { return }
        budget -= 1
        if classes(el).contains(where: { $0.contains("message-row") }) {
            rows.append(el)
            return
        }
        for c in children(el) { findMessageRows(c, into: &rows, budget: &budget) }
    }

    private static func findAll(role wanted: String, in el: AXUIElement, depth: Int = 0, into out: inout [AXUIElement]) {
        if role(el) == wanted { out.append(el); return }
        guard depth < 30 else { return }
        for c in children(el) { findAll(role: wanted, in: c, depth: depth + 1, into: &out) }
    }

    /// 대화 제목: 상단 헤더(dframe-header)의 제목 버튼.
    private static func findTitle(in el: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 40 else { return nil }
        if classes(el).contains(where: { $0.contains("dframe-header") }) {
            var headings: [AXUIElement] = []
            findAll(role: kAXHeadingRole as String, in: el, into: &headings)
            for h in headings {
                for e in [h] + children(h) {
                    for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                        if let t = attr(e, key) as? String, !t.trimmingCharacters(in: .whitespaces).isEmpty {
                            return t
                        }
                    }
                }
            }
            return nil
        }
        for c in children(el) {
            if let t = findTitle(in: c, depth: depth + 1) { return t }
        }
        return nil
    }

    /// 진단용: 메시지 줄의 클래스 구조 (텍스트 내용 없이).
    private static func rowSignature(_ el: AXUIElement) -> String {
        var parts: [String] = []
        func visit(_ e: AXUIElement, _ depth: Int) {
            guard depth <= 3, parts.count < 12 else { return }
            let c = classes(e)
            if !c.isEmpty {
                parts.append(String(repeating: ">", count: depth) + c.prefix(10).joined(separator: "."))
            }
            for k in children(e) { visit(k, depth + 1) }
        }
        visit(el, 0)
        let x = frame(el).map { "x=\(Int($0.minX)) w=\(Int($0.width))" } ?? ""
        return "[\(x)] " + parts.joined(separator: " | ")
    }

    static func readConversation(pid: pid_t) -> Conversation? {
        guard let window = mainWindow(pid: pid) else { return nil }

        // 창 안에 웹 화면이 여러 개일 수 있다 → 메시지가 있는 쪽을 고른다
        var webAreas: [AXUIElement] = []
        findAll(role: "AXWebArea", in: window, into: &webAreas)
        guard !webAreas.isEmpty else { return nil }

        var rows: [AXUIElement] = []
        var web = webAreas[0]
        for w in webAreas {
            var found: [AXUIElement] = []
            var budget = 40_000
            findMessageRows(w, into: &found, budget: &budget)
            if !found.isEmpty { rows = found; web = w; break }
        }

        let windowTitle = (attr(window, kAXTitleAttribute) as? String) ?? "Claude"
        let title = findTitle(in: web) ?? windowTitle

        var blocks: [TranscriptBlock] = []
        var methods: [String] = []
        if !rows.isEmpty {
            var budget = 80_000
            var kinds: [TranscriptBlock.Kind?] = []
            var texts: [String] = []
            for row in rows {
                var leaves: [Leaf] = []
                collectText(row, into: &leaves, budget: &budget)
                let text = join(leaves)
                guard !text.isEmpty else { continue }
                texts.append(text)
                kinds.append(classifyByClasses(row))
            }
            // 클래스로 구분 못 한 줄은 '질문 → 답변이 번갈아 나온다'는 규칙으로 채운다
            var previous: TranscriptBlock.Kind?
            for (i, text) in texts.enumerated() {
                let kind: TranscriptBlock.Kind
                if let k = kinds[i] {
                    kind = k
                    methods.append("class")
                } else {
                    kind = previous == .user ? .assistant : .user
                    methods.append("alternate")
                }
                blocks.append(TranscriptBlock(kind: kind, text: text))
                previous = kind
            }
            let methodCount = Dictionary(grouping: methods, by: { $0 }).mapValues(\.count)
            DebugLog.log("readConversation: webAreas=\(webAreas.count) rows=\(rows.count) blocks=\(blocks.count) 구분=\(methodCount)\n"
                         + rows.prefix(3).map { "  row " + rowSignature($0) }.joined(separator: "\n"))
        }

        // 메시지 단서를 못 찾으면 화면 전체 텍스트를 한 덩어리로 보낸다.
        if blocks.isEmpty {
            var best = ""
            for w in webAreas {
                var leaves: [Leaf] = []
                var b = 60_000
                collectText(w, into: &leaves, budget: &b)
                let text = join(leaves)
                if text.count > best.count { best = text }
            }
            guard !best.isEmpty else { return nil }
            blocks = [TranscriptBlock(kind: .unknown, text: best)]
            DebugLog.log("readConversation: message-row 없음 → 전체 텍스트 \(best.count)자 한 덩어리")
        }
        return Conversation(title: title, blocks: blocks)
    }
}
