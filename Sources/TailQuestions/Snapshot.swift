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
        renderView("diagram-flow", into: dir, size: NSSize(width: 860, height: 250), FlowDiagram())
    }

    private static func renderView<V: View>(_ name: String, into dir: URL, size: NSSize, _ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = dir.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("✅ \(url.path)")
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


/// README '작동 방식' 그림
struct FlowDiagram: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                step(icon: Image(systemName: "cursorarrow.and.square.on.square.dashed"), tint: Theme.text,
                     title: "Claude 데스크톱", detail: "답변을 드래그하고\n⌥ ⇧ Space")
                arrow("화면 읽기")
                step(icon: Image(nsImage: AppIcon.image), tint: nil,
                     title: "TailQuestions", detail: "대화 전체 + 선택 부분\n+ 내 꼬리질문")
                arrow("질문")
                step(icon: Image(systemName: "terminal"), tint: Theme.branch,
                     title: "Claude Code", detail: "내 Claude 구독으로\n답변 생성")
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                Text("답변은 패널에만 남고, Claude 본 대화는 그대로예요")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.sunken))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
    }

    private func step(icon: Image, tint: Color?, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Group {
                if let tint {
                    icon.font(.system(size: 20, weight: .medium)).foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.sunken))
                } else {
                    icon.resizable().frame(width: 48, height: 48)
                }
            }
            .frame(height: 48)
            Text(title).font(.system(size: 14, weight: .bold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize()
        }
        .frame(width: 190)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private func arrow(_ label: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.main)
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.main)
        }
        .frame(maxWidth: .infinity)
    }
}
