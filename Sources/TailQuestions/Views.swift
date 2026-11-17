import AppKit
import SwiftUI

// MARK: - 루트

struct PanelRootView: View {
    @EnvironmentObject var model: AppModel
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Rectangle().fill(Theme.border).frame(height: 1)
            Group {
                if model.showOnboarding || !model.isReady {
                    OnboardingView()
                } else if model.showSettings {
                    SettingsView()
                } else if let thread = model.current {
                    ThreadView(thread: thread)
                } else {
                    TreeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 320, minHeight: 420)
        .task { await model.refreshSetup() }
        .onReceive(timer) { _ in
            guard !model.snapshotMode else { return }
            let trusted = AXReader.isTrusted(prompt: false)
            if trusted != model.setup.accessibility { model.setup.accessibility = trusted }
        }
    }
}

// MARK: - 헤더 (창 신호등 버튼과 같은 줄)

struct HeaderView: View {
    @EnvironmentObject var model: AppModel

    private var inThread: Bool {
        model.current != nil && !model.showSettings && !model.showOnboarding && model.isReady
    }

    var body: some View {
        HStack(spacing: 4) {
            if model.snapshotMode {
                FakeTrafficLights().padding(.leading, 14)
                Spacer().frame(width: 12)
            } else {
                Spacer().frame(width: 76)
            }

            if inThread {
                Button { model.showTree() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text("main").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.main)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.mainSoft))
                }
                .buttonStyle(.plain)
                .help("main 대화와 가지 목록으로")
            } else {
                Text(model.showSettings ? "설정" : "꼬리질문")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            HistoryMenu()
            IconButton(systemName: model.docked ? "pin.fill" : "pin.slash",
                       active: model.docked,
                       help: model.docked ? "Claude 창에 붙어 다니는 중" : "자유롭게 이동") {
                model.docked.toggle()
            }
            IconButton(systemName: "gearshape", active: model.showSettings, help: "설정") {
                model.showSettings.toggle()
            }
        }
        .padding(.trailing, 10)
        .frame(height: 40)
    }
}

struct FakeTrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { hex in
                Circle()
                    .fill(Color(red: Double((hex >> 16) & 0xff) / 255,
                                green: Double((hex >> 8) & 0xff) / 255,
                                blue: Double(hex & 0xff) / 255))
                    .frame(width: 12, height: 12)
            }
        }
    }
}

struct HistoryMenu: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Menu {
            if model.threads.isEmpty { Text("아직 가지가 없어요") }
            ForEach(model.conversationsInHistory, id: \.key) { group in
                Section(group.title) {
                    ForEach(group.threads) { t in
                        Button(t.displayTitle) {
                            model.showSettings = false
                            model.select(t.id)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
        .help("모든 대화의 가지 기록")
    }
}

// MARK: - 트리 (main + 가지)

struct TreeView: View {
    @EnvironmentObject var model: AppModel
    @State private var refreshing = false
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.setup.accessibility { AccessBanner() }

                    if let conv = model.activeConversation, !conv.turns.isEmpty {
                        conversationHeader(conv)
                        VStack(alignment: .leading, spacing: 0) {
                            let turns = conv.turns
                            ForEach(turns) { turn in
                                TurnRow(turn: turn, conv: conv, isLast: turn.id == turns.count - 1)
                            }
                        }
                        let loose = model.looseBranches(of: conv)
                        if !loose.isEmpty { branchSection("다른 가지", loose) }
                    } else {
                        EmptyConversationCard(refreshing: refreshing, refresh: refresh)
                        if !model.threads.isEmpty {
                            branchSection("최근 가지", Array(model.threads.prefix(8)))
                        }
                    }
                }
                .padding(16)
            }

            Composer(text: $input,
                     placeholder: model.activeConversation == nil ? "바로 질문하기" : "이 대화에서 새 가지로 질문하기",
                     isSending: false,
                     onSend: { model.askNew(input); input = "" },
                     onStop: {})
        }
    }

    private func conversationHeader(_ conv: Conversation) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("지금 대화")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                Text(conv.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
            }
            Spacer()
            IconButton(systemName: "arrow.clockwise", help: "Claude 화면에서 대화를 다시 읽어요", action: refresh)
                .disabled(refreshing)
        }
    }

    private func branchSection(_ title: String, _ threads: [TailThread]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            ForEach(threads) { BranchPill(thread: $0) }
        }
    }

    private func refresh() {
        Task {
            refreshing = true
            await model.refreshConversation?()
            refreshing = false
        }
    }
}

struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("손쉬운 사용 권한이 꺼져 있어요").font(.system(size: 12, weight: .semibold))
                Text("Claude 대화를 읽을 수 없어서 맥락 없이 질문돼요.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("켜기") { Permissions.openAccessibility() }
                .buttonStyle(PillButtonStyle())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.branchSoft))
    }
}

struct EmptyConversationCard: View {
    @EnvironmentObject var model: AppModel
    let refreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.main)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Theme.mainSoft))
            Text("Claude에서 궁금한 부분을 드래그하고\n⌥ ⇧ Space 를 눌러 보세요")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("아무것도 선택하지 않고 누르면 이 대화의 질문 목록이 나와요.\n각 질문에서 가지를 쳐서 따로 물어볼 수 있어요.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button(refreshing ? "읽는 중…" : "Claude 화면 다시 읽기", action: refresh)
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(refreshing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

/// main 의 커밋 하나(내 질문)와 거기서 뻗은 가지들.
struct TurnRow: View {
    @EnvironmentObject var model: AppModel
    let turn: Conversation.Turn
    let conv: Conversation
    let isLast: Bool
    @State private var hovering = false

    private let rail: CGFloat = 14

    var body: some View {
        let branches = model.branches(of: conv, turn: turn)
        HStack(alignment: .top, spacing: 10) {
            // main 줄기
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.main.opacity(0.28))
                    .frame(width: 2)
                    .padding(.top, isFirstTurn ? 9 : 0)
                    .frame(maxHeight: isLast && branches.isEmpty ? 9 : .infinity, alignment: .top)
                Circle()
                    .fill(Theme.main)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 2.5))
                    .padding(.top, 4)
            }
            .frame(width: rail)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Text(turn.question)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .help(turn.question)
                    Spacer(minLength: 4)
                    Button {
                        model.startThread(at: turn, in: conv)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            Text("가지").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.branch)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.branchSoft))
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering ? 1 : 0)
                    .help("이 질문에서 가지 치기")
                }

                ForEach(branches) { b in
                    BranchPill(thread: b)
                        .padding(.leading, 14)
                        .overlay(alignment: .topLeading) {
                            BranchConnector()
                                .stroke(Theme.branch, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 10 + rail / 2 + 12, height: 22)
                                .offset(x: -(10 + rail / 2), y: -8)
                        }
                }
            }
            .padding(.bottom, 18)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var isFirstTurn: Bool { turn.id == 0 }
}

/// main 줄기에서 오른쪽으로 휘어 나가는 가지 선.
struct BranchConnector: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: rect.height - 10))
        p.addQuadCurve(to: CGPoint(x: 10, y: rect.height), control: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        return p
    }
}

struct BranchPill: View {
    @EnvironmentObject var model: AppModel
    let thread: TailThread
    @State private var hovering = false

    var body: some View {
        Button {
            model.select(thread.id)
        } label: {
            HStack(spacing: 8) {
                Text(thread.displayTitle)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                let count = thread.messages.filter { $0.role == .user }.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.branch)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.branchSoft))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Theme.branchSoft : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(hovering ? Theme.branch.opacity(0.5) : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("가지 삭제", role: .destructive) { model.delete(thread.id) }
        }
    }
}

// MARK: - 가지 대화

struct ThreadView: View {
    @EnvironmentObject var model: AppModel
    let thread: TailThread
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ContextCard(thread: thread)
                        ForEach(thread.messages) { m in
                            MessageView(role: m.role, text: m.text)
                        }
                        if let streaming = model.streamingText {
                            if streaming.isEmpty {
                                TypingIndicator()
                            } else {
                                MessageView(role: .assistant, text: streaming)
                            }
                        }
                        if let err = model.errorText {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                                Text(err).font(.system(size: 12)).textSelection(.enabled)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.danger.opacity(0.08)))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: model.streamingText) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: thread.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            Composer(text: $input,
                     placeholder: thread.messages.isEmpty ? "이 부분에 대해 궁금한 점" : "이어서 질문하기",
                     isSending: model.isSending,
                     onSend: { model.send(input); input = "" },
                     onStop: { model.cancelSending() })
        }
    }
}

struct ContextCard: View {
    let thread: TailThread
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let q = thread.mainQuestion {
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.main).frame(width: 8, height: 8).padding(.top, 4)
                    Text(q)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(expanded ? nil : 2)
                        .textSelection(.enabled)
                }
            }
            if !thread.selection.isEmpty {
                Text(thread.selection)
                    .font(.system(size: 12.5))
                    .lineLimit(expanded ? nil : 4)
                    .textSelection(.enabled)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Theme.branch).frame(width: 3)
                    }
            }
            HStack {
                Label(thread.transcript.isEmpty ? "대화 맥락 없음" : "대화 전체를 맥락으로 사용",
                      systemImage: thread.transcript.isEmpty ? "circle.slash" : "text.bubble")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                if (thread.mainQuestion?.count ?? 0) > 60 || thread.selection.count > 120 {
                    Button(expanded ? "접기" : "펼치기") { expanded.toggle() }
                        .font(.system(size: 10.5, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.main)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sunken))
    }
}

struct MessageView: View {
    let role: ChatMessage.Role
    let text: String

    var body: some View {
        if role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.mainSoft))
            }
        } else {
            Text(markdown)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var markdown: AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.branch)
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * max(0, sin(phase + Double(i) * 0.9)))
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}

struct Composer: View {
    @Binding var text: String
    let placeholder: String
    let isSending: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var focused: Bool
    @EnvironmentObject var model: AppModel

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit { if canSend && !isSending { onSend() } }
                .padding(.vertical, 4)
            Button {
                isSending ? onStop() : onSend()
            } label: {
                Image(systemName: isSending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isSending || canSend ? Theme.main : Theme.tertiary.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .disabled(!isSending && !canSend)
            .help(isSending ? "중지" : "보내기 (Return)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(focused ? Theme.main.opacity(0.5) : Theme.border))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .padding(12)
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { focused = true }
    }
}

// MARK: - 처음 설정

enum Permissions {
    static func openAccessibility() {
        AXReader.isTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var copied = false
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(nsImage: AppIcon.image)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("꼬리질문 시작하기").font(.system(size: 17, weight: .bold))
                        Text("세 가지만 준비하면 돼요").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }

                StepCard(number: 1, done: model.setup.claudeCodePath != nil,
                         title: "Claude Code 설치",
                         detail: "지금 쓰는 Claude 구독으로 답하기 위해 필요해요. 터미널에 아래 명령을 붙여넣고 실행하세요.") {
                    if model.setup.claudeCodePath == nil {
                        HStack(spacing: 6) {
                            Text(ClaudeCodeClient.installCommand)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer(minLength: 4)
                            Button(copied ? "복사됨" : "복사") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ClaudeCodeClient.installCommand, forType: .string)
                                copied = true
                            }
                            .buttonStyle(PillButtonStyle(prominent: false))
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.sunken))
                        Button("터미널 열기") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }

                StepCard(number: 2, done: model.setup.loggedIn == true,
                         title: "Claude 계정 로그인",
                         detail: "Claude 앱과 같은 계정으로 로그인해요. 브라우저가 열리면 승인하세요.") {
                    if model.setup.loggedIn != true {
                        HStack(spacing: 8) {
                            Button(model.loggingIn ? "브라우저에서 로그인 기다리는 중…" : "로그인") { model.login() }
                                .buttonStyle(PillButtonStyle())
                                .disabled(model.setup.claudeCodePath == nil || model.loggingIn)
                            Button("터미널에서 로그인") { ClaudeCodeClient.loginInTerminal() }
                                .buttonStyle(PillButtonStyle(prominent: false))
                                .disabled(model.setup.claudeCodePath == nil)
                        }
                    }
                }

                StepCard(number: 3, done: model.setup.accessibility,
                         title: "손쉬운 사용 권한",
                         detail: "Claude 화면의 대화와 드래그한 텍스트를 읽기 위해 필요해요. 목록에서 TailQuestions를 켜 주세요.") {
                    if !model.setup.accessibility {
                        Button("설정 열기") { Permissions.openAccessibility() }
                            .buttonStyle(PillButtonStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("사용법").font(.system(size: 12, weight: .semibold))
                    Text("Claude에서 궁금한 부분을 드래그하고 **⌥ ⇧ Space**. 선택 없이 누르면 대화의 질문 목록에서 가지를 칠 수 있어요.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }

                HStack {
                    Button("API 키로 대신 쓰기") {
                        model.backend = .api
                        model.finishOnboarding()
                        model.showSettings = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("시작하기") { model.finishOnboarding() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(!model.isReady)
                }
            }
            .padding(20)
        }
        .onReceive(poll) { _ in
            Task {
                if model.setup.claudeCodePath == nil || model.setup.loggedIn != true {
                    await model.refreshSetup()
                }
            }
        }
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.success : Theme.mainSoft).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.main)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(done ? Theme.secondary : Theme.text)
                if !done {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    content()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}

// MARK: - 설정

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var key = ""

    var body: some View {
        Form {
            Section("연결 방식") {
                Picker("연결 방식", selection: $model.backend) {
                    ForEach(Backend.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                switch model.backend {
                case .claudeCode:
                    Text(model.setup.loggedIn == true
                         ? "✅ 로그인됨 · 지금 쓰는 Claude 구독으로 답해요 (추가 요금 없음)"
                         : "⚠️ Claude Code 설치·로그인이 필요해요")
                        .font(.caption).foregroundStyle(Theme.secondary)
                case .api:
                    SecureField("sk-ant-…", text: $key)
                    HStack {
                        Button("저장") { model.saveAPIKey(key); key = "" }
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                        if model.hasAPIKey {
                            Text("저장된 키가 있어요").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                    Text("키는 이 Mac의 키체인에만 저장돼요. 구독과 별도로 사용량만큼 요금이 나가요.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }

            Section("모델") {
                Picker("모델", selection: $model.model) {
                    ForEach(ClaudeClient.models, id: \.id) { m in Text(m.name).tag(m.id) }
                }
                .labelsHidden()
            }

            Section("실행") {
                Toggle("Mac에 로그인하면 자동으로 실행", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let note = model.launchAtLoginNote {
                    Text(note).font(.caption).foregroundStyle(Theme.warning)
                }
            }

            Section("권한") {
                HStack {
                    Text(model.setup.accessibility ? "✅ 손쉬운 사용 권한 있음" : "⚠️ 손쉬운 사용 권한 필요")
                    Spacer()
                    Button("설정 열기") { Permissions.openAccessibility() }
                }
            }

            Section {
                Button("설정 도우미 다시 보기") {
                    model.showSettings = false
                    model.showOnboarding = true
                }
                Button("닫기") { model.showSettings = false }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
