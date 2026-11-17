import AppKit
import SwiftUI

/// README용 스크린샷을 실제 화면 코드로 그린다.
///   TailQuestions --snapshot docs/
@MainActor
enum Snapshot {
    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        render("screenshot-tree", into: dir) { m in m.select(nil) }
        render("screenshot-thread", into: dir) { m in m.select(m.threads.first?.id) }
        render("screenshot-onboarding", into: dir) { m in
            m.setup.loggedIn = false
            m.setup.accessibility = false
            m.showOnboarding = true
        }
    }

    private static func render(_ name: String, into dir: URL, configure: (AppModel) -> Void) {
        let model = demoModel()
        configure(model)
        let host = NSHostingView(rootView: PanelRootView().environmentObject(model))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 660)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = dir.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("✅ \(url.path)")
    }

    private static func demoModel() -> AppModel {
        let m = AppModel(snapshotMode: true)
        m.setup.claudeCodePath = "/usr/local/bin/claude"
        m.setup.loggedIn = true
        m.setup.accessibility = true
        m.showOnboarding = false

        let q1 = "인턴 공고 설명해줘"
        let q2 = "정밀도랑 재현율 차이를 쉽게 알려줘"
        let q3 = "지원서에는 뭘 강조하면 좋을까?"
        let conv = Conversation(title: "Claude", blocks: [
            .init(kind: .user, text: q1),
            .init(kind: .assistant, text: "LLM에게 Java/Spring 코드를 읽혀서 API 설명서를 자동으로 만들고, 개인정보가 오가는 필드를 찾아내는 도구를 만드는 자리예요. 업무: 정답 데이터셋 구축 — 실제 API 문서와 사람 검수 결과로 \"정답지\" 만들기"),
            .init(kind: .user, text: q2),
            .init(kind: .assistant, text: "정밀도는 AI가 개인정보라고 한 것 중 진짜 비율, 재현율은 진짜 개인정보 중 AI가 찾아낸 비율이에요."),
            .init(kind: .user, text: q3),
            .init(kind: .assistant, text: "평가셋을 직접 설계해 본 경험과 오류 분석 경험을 강조하면 좋아요."),
        ])
        m.conversation = conv

        func thread(_ main: String, _ selection: String, _ msgs: [(ChatMessage.Role, String)]) -> TailThread {
            var t = TailThread(conversationTitle: conv.title, conversationKey: conv.key, mainQuestion: main,
                               selection: selection, transcript: conv.blocks)
            t.messages = msgs.map { ChatMessage(role: $0.0, text: $0.1) }
            return t
        }
        m.threads = [
            thread(q1, "실제 API 문서와 사람 검수 결과로 \"정답지\" 만들기", [
                (.user, "정답지는 누가 만들어?"),
                (.assistant, "보통 **현업 개발자와 인턴**이 함께 만들어요. 실제 API 문서를 기준으로 각 필드가 무엇인지, 개인정보인지를 사람이 하나씩 확인해서 표시해요.\n\n이렇게 만든 정답지가 있어야 LLM 결과를 채점할 수 있어요."),
                (.user, "그럼 검수 기준은 누가 정해?"),
                (.assistant, "보통 팀이 먼저 **라벨링 가이드**를 만들어요. \"이름·전화번호·주민번호는 개인정보\"처럼 기준을 문서로 정하고, 애매한 경우는 회의로 정해서 가이드에 추가해요."),
            ]),
            thread(q1, "OpenAPI 스펙 생성", [(.user, "Swagger랑 OpenAPI는 같은 거야?")]),
            thread(q2, "", [(.user, "예시 하나만 더 들어줘")]),
        ]
        return m
    }
}
