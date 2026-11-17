import SwiftUI

struct PanelRootView: View {
    @EnvironmentObject var model: AppModel
    @State private var trusted = AXReader.isTrusted(prompt: false)
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            if !trusted && !model.showSettings {
                PermissionBanner()
            }
            if !model.isReady || model.showSettings {
                SettingsView()
            } else if let thread = model.current {
                ThreadView(thread: thread)
            } else {
                TreeView()
            }
        }
        .padding(.top, 22) // 투명 타이틀바 영역
        .frame(minWidth: 300, minHeight: 400)
        .background(.regularMaterial)
        .onReceive(timer) { _ in trusted = AXReader.isTrusted(prompt: false) }
    }
}

struct PermissionBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("⚠️ 손쉬운 사용 권한이 없어요").font(.callout.bold())
            Text("Claude 화면의 대화와 드래그한 텍스트를 읽을 수 없어요. 아래 칸에서 질문은 할 수 있지만 맥락이 빠져요.\n이미 켜져 있다면 목록에서 TailQuestions를 − 로 지우고 다시 추가해 주세요 (다시 빌드하면 권한이 풀려요).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("손쉬운 사용 설정 열기") {
                    AXReader.isTrusted(prompt: true)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("앱 위치 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }
}

// MARK: - 헤더

struct HeaderView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.current != nil && !model.showSettings {
                Button { model.showTree() } label: {
                    Label("main", systemImage: "chevron.left")
                }
                .help("main 대화와 가지 목록으로")
            } else {
                Label("꼬리질문", systemImage: "arrow.triangle.branch").font(.headline)
            }

            Spacer()

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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("모든 대화의 가지 기록")

            Button { model.docked.toggle() } label: {
                Image(systemName: model.docked ? "pin.fill" : "pin.slash")
            }
            .help(model.docked ? "Claude 창에 붙어 다니는 중" : "자유롭게 이동")

            Button { model.showSettings.toggle() } label: {
                Image(systemName: "gearshape")
            }
            .help("설정")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 트리 (main + 가지)

struct TreeView: View {
    @EnvironmentObject var model: AppModel
    @State private var refreshing = false
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            tree
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(model.activeConversation == nil ? "바로 질문하기…" : "이 대화에 대해 새 가지로 질문…",
                          text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .onSubmit(submit)
                Button(action: submit) { Image(systemName: "arrow.up.circle.fill") }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: 14))
            .buttonStyle(.borderless)
            .imageScale(.large)
            .padding(12)
        }
    }

    private func submit() {
        model.askNew(input)
        input = ""
    }

    private var tree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let conv = model.activeConversation {
                    HStack {
                        Text(conv.displayTitle).font(.subheadline.bold()).lineLimit(1)
                        Spacer()
                        refreshButton
                    }
                    .padding(.bottom, 12)

                    let turns = conv.turns
                    if turns.isEmpty {
                        Text("이 대화의 질문을 구분하지 못했어요. 드래그 후 ⌥⇧Space로 가지를 만들 수 있어요.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.bottom, 12)
                    }
                    ForEach(turns) { turn in
                        TurnRow(turn: turn, conv: conv, isLast: turn.id == turns.count - 1)
                    }

                    let loose = model.looseBranches(of: conv)
                    if !loose.isEmpty {
                        Text("기타 가지").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(loose) { BranchRow(thread: $0) }
                    }
                } else {
                    HowToView()
                    HStack { Spacer(); refreshButton; Spacer() }
                }
            }
            .padding(14)
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                refreshing = true
                await model.refreshConversation?()
                refreshing = false
            }
        } label: {
            Label("Claude 화면 다시 읽기", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .disabled(refreshing)
        .help("Claude 화면에서 대화를 다시 읽어요")
    }
}

/// main 브랜치의 커밋 하나(내 질문)와 거기서 뻗은 가지들.
struct TurnRow: View {
    @EnvironmentObject var model: AppModel
    let turn: Conversation.Turn
    let conv: Conversation
    let isLast: Bool
    @State private var hovering = false

    var body: some View {
        let branches = model.branches(of: conv, turn: turn)
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Color.secondary.opacity(isLast ? 0 : 0.35))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 6) {
                Text(turn.question)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .help(turn.question)

                ForEach(branches) { BranchRow(thread: $0) }

                Button {
                    model.startThread(at: turn, in: conv)
                } label: {
                    Label("여기서 가지 치기", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .opacity(hovering || branches.isEmpty ? 1 : 0.35)
            }
            .padding(.bottom, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering = $0 }
    }
}

struct BranchRow: View {
    @EnvironmentObject var model: AppModel
    let thread: TailThread

    var body: some View {
        Button {
            model.select(thread.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.orange)
                Text(thread.displayTitle)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if !thread.messages.isEmpty {
                    Text("\(thread.messages.count / 2 + thread.messages.count % 2)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12.5))
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("가지 삭제", role: .destructive) { model.delete(thread.id) }
        }
    }
}

struct HowToView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("꼬리질문 하는 법").font(.headline)
            Text("Claude 대화에서 궁금한 부분을 드래그하고\n**⌥ ⇧ Space** 를 누르세요.\n\n아무것도 선택하지 않고 누르면\n대화의 질문 목록에서 가지를 칠 수 있어요.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 가지 대화

struct ThreadView: View {
    @EnvironmentObject var model: AppModel
    let thread: TailThread
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ContextCard(thread: thread)
                        ForEach(thread.messages) { m in
                            MessageView(role: m.role, text: m.text)
                        }
                        if let streaming = model.streamingText {
                            MessageView(role: .assistant, text: streaming.isEmpty ? "생각 중…" : streaming)
                                .opacity(streaming.isEmpty ? 0.5 : 1)
                        }
                        if let err = model.errorText {
                            Text(err).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .onChange(of: model.streamingText) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: thread.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(thread.messages.isEmpty ? "이 부분에 대해 궁금한 점…" : "꼬리의 꼬리질문…",
                          text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit(submit)
                if model.isSending {
                    Button { model.cancelSending() } label: { Image(systemName: "stop.circle.fill") }
                        .help("중지")
                } else {
                    Button(action: submit) { Image(systemName: "arrow.up.circle.fill") }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .font(.system(size: 14))
            .buttonStyle(.borderless)
            .imageScale(.large)
            .padding(12)
        }
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) { inputFocused = true }
    }

    private func submit() {
        guard !model.isSending else { return }
        model.send(input)
        input = ""
    }
}

struct ContextCard: View {
    let thread: TailThread
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let q = thread.mainQuestion {
                Label("main 질문", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Text(q)
                    .font(.callout)
                    .lineLimit(expanded ? nil : 2)
                    .textSelection(.enabled)
            }
            if !thread.selection.isEmpty {
                Label("선택한 부분", systemImage: "text.quote").font(.caption).foregroundStyle(.secondary)
                Text(thread.selection)
                    .font(.callout)
                    .lineLimit(expanded ? nil : 4)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.orange).frame(width: 3)
                    }
                    .textSelection(.enabled)
            }
            HStack {
                Text(thread.transcript.isEmpty
                     ? "대화 내용을 읽지 못했어요 (선택한 부분만 보냄)"
                     : "대화 \(thread.transcript.count)개 블록을 맥락으로 함께 보냄")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(expanded ? "접기" : "펼치기") { expanded.toggle() }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

struct MessageView: View {
    let role: ChatMessage.Role
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role == .user ? "나" : "Claude")
                .font(.caption.bold())
                .foregroundStyle(role == .user ? Color.accentColor : .orange)
            Text(markdown)
                .font(.system(size: 13.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var markdown: AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
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
                    if let path = ClaudeCodeClient.binaryPath {
                        Text("✅ Claude Code 찾음: \(path)\n지금 쓰는 Claude 구독으로 답해요. 추가 요금 없이 구독 사용량에서 차감돼요.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("⚠️ Claude Code(claude)를 찾지 못했어요. 설치 후 터미널에서 `claude`로 로그인해 주세요.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                case .api:
                    SecureField("sk-ant-…", text: $key)
                    HStack {
                        Button("저장") {
                            model.saveAPIKey(key)
                            key = ""
                        }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                        if model.hasAPIKey {
                            Text("저장된 키가 있어요").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("키는 이 Mac의 키체인에만 저장돼요. 구독과 별도로 사용량만큼 요금이 나가요.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("권한") {
                HStack {
                    Text(AXReader.isTrusted(prompt: false) ? "✅ 손쉬운 사용 권한 있음" : "⚠️ 손쉬운 사용 권한 필요")
                    Spacer()
                    Button("설정 열기") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                Text("Claude 화면의 대화와 선택한 텍스트를 읽는 데 필요해요.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if model.isReady {
                Button("닫기") { model.showSettings = false }
            }
        }
        .formStyle(.grouped)
    }
}
