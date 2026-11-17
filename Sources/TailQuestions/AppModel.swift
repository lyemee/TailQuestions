import Foundation
import ServiceManagement
import SwiftUI

enum Backend: String, CaseIterable, Identifiable {
    case claudeCode, api
    var id: String { rawValue }
    var label: String {
        switch self {
        case .claudeCode: return "Claude 구독 (Claude Code 로그인)"
        case .api: return "Anthropic API 키"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var threads: [TailThread] = []
    /// nil 이면 트리(main + 가지들) 화면, 값이 있으면 그 가지의 대화 화면.
    @Published var currentID: UUID?
    /// 지금 보고 있는 메인 대화 (Claude 화면에서 가장 최근에 읽은 것).
    @Published var conversation: Conversation?
    @Published var streamingText: String?
    @Published var isSending = false
    @Published var errorText: String?
    @Published var hasAPIKey = Keychain.load() != nil
    @Published var showSettings = false
    @Published var focusToken = UUID()

    @Published var backend: Backend = Backend(rawValue: UserDefaults.standard.string(forKey: "backend") ?? "")
        ?? (ClaudeCodeClient.binaryPath != nil ? .claudeCode : .api) {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend") }
    }
    @Published var docked: Bool = UserDefaults.standard.object(forKey: "docked") as? Bool ?? true {
        didSet { UserDefaults.standard.set(docked, forKey: "docked") }
    }
    @Published var model: String = UserDefaults.standard.string(forKey: "model") ?? "claude-opus-5-5" {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }

    // MARK: 로그인 시 자동 실행

    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchAtLoginNote: String?

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            DebugLog.log("launchAtLogin error: \(error.localizedDescription)")
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginNote = "시스템 설정 → 일반 → 로그인 항목에서 TailQuestions를 허용해 주세요."
            SMAppService.openSystemSettingsLoginItems()
        } else {
            launchAtLoginNote = nil
        }
    }

    /// Claude 화면을 다시 읽어오는 함수 (AppDelegate가 연결).
    var refreshConversation: (() async -> Void)?

    private var sendTask: Task<Void, Never>?

    init() { load() }

    var isReady: Bool {
        switch backend {
        case .claudeCode: return ClaudeCodeClient.binaryPath != nil
        case .api: return hasAPIKey
        }
    }

    var current: TailThread? {
        guard let currentID else { return nil }
        return threads.first { $0.id == currentID }
    }

    /// 트리에 보여줄 대화: Claude 화면에서 읽은 것, 없으면 보고 있던 가지의 대화.
    var activeConversation: Conversation? {
        conversation ?? current?.conversation ?? threads.first?.conversation
    }

    func branches(of conv: Conversation) -> [TailThread] {
        threads.filter { ($0.conversationKey ?? $0.conversation.key) == conv.key }
    }

    func branches(of conv: Conversation, turn: Conversation.Turn) -> [TailThread] {
        branches(of: conv).filter { TextUtil.sameText($0.mainQuestion, turn.question) }
    }

    /// 어느 질문에도 매칭되지 않는 가지들.
    func looseBranches(of conv: Conversation) -> [TailThread] {
        let questions = conv.turns.map(\.question)
        return branches(of: conv).filter { t in !questions.contains { TextUtil.sameText($0, t.mainQuestion) } }
    }

    /// 다른 대화들의 가지 (기록 메뉴용).
    var conversationsInHistory: [(key: String, title: String, threads: [TailThread])] {
        var order: [String] = []
        var map: [String: (String, [TailThread])] = [:]
        for t in threads {
            let key = t.conversationKey ?? t.conversation.key
            if map[key] == nil { order.append(key); map[key] = (t.conversation.displayTitle, []) }
            map[key]!.1.append(t)
        }
        return order.map { (key: $0, title: map[$0]!.0, threads: map[$0]!.1) }
    }

    // MARK: 가지 만들기 / 이동

    /// 드래그한 텍스트로 가지를 만든다.
    func startThread(selection: String, conversation: Conversation?) {
        if let conversation { self.conversation = conversation }
        let blocks = conversation?.blocks ?? []
        createThread(
            conversation: conversation,
            mainQuestion: TextUtil.findMainQuestion(selection: selection, in: blocks),
            selection: selection.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// 선택 없이 바로 묻기: 지금 대화 전체를 맥락으로 새 가지를 만들고 곧바로 보낸다.
    func askNew(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        createThread(conversation: activeConversation, mainQuestion: activeConversation?.turns.last?.question, selection: "")
        send(q)
    }

    /// 트리에서 특정 질문(커밋)에 새 가지를 만든다.
    func startThread(at turn: Conversation.Turn, in conv: Conversation) {
        createThread(conversation: conv, mainQuestion: turn.question, selection: "")
    }

    private func createThread(conversation: Conversation?, mainQuestion: String?, selection: String) {
        let thread = TailThread(
            conversationTitle: conversation?.title ?? "",
            conversationKey: conversation?.key,
            mainQuestion: mainQuestion,
            selection: selection,
            transcript: conversation?.blocks ?? []
        )
        threads.insert(thread, at: 0)
        select(thread.id)
        save()
    }

    func select(_ id: UUID?) {
        cancelSending()
        currentID = id
        errorText = nil
        focusToken = UUID()
    }

    func showTree() {
        if let t = current, conversation?.key != t.conversation.key {
            conversation = t.conversation
        }
        select(nil)
    }

    func delete(_ id: UUID) {
        if currentID == id { select(nil) }
        threads.removeAll { $0.id == id }
        save()
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(trimmed)
        hasAPIKey = !trimmed.isEmpty
    }

    // MARK: 질문 보내기

    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending,
              let idx = threads.firstIndex(where: { $0.id == currentID }) else { return }

        threads[idx].messages.append(ChatMessage(role: .user, text: question))
        save()

        let thread = threads[idx]
        let threadID = thread.id
        let system = Prompt.system(for: thread)
        let backend = self.backend
        let model = self.model

        isSending = true
        errorText = nil
        streamingText = ""

        sendTask = Task { [weak self] in
            let onText: @MainActor (String) -> Void = { chunk in
                self?.streamingText = (self?.streamingText ?? "") + chunk
            }
            do {
                let stop: String?
                switch backend {
                case .claudeCode:
                    guard let bin = ClaudeCodeClient.binaryPath else {
                        throw ClaudeError.stream("Claude Code(claude)를 찾을 수 없어요. 설정에서 API 키 방식을 선택해 주세요.")
                    }
                    stop = try await ClaudeCodeClient(binary: bin, model: model)
                        .stream(system: system, prompt: Prompt.singlePrompt(for: thread), onText: onText)
                case .api:
                    guard let key = Keychain.load() else {
                        throw ClaudeError.stream("API 키가 없어요. 설정에서 입력해 주세요.")
                    }
                    stop = try await ClaudeClient(apiKey: key, model: model)
                        .stream(system: system, messages: Prompt.apiMessages(for: thread), onText: onText)
                }
                guard let self else { return }
                var answer = self.streamingText ?? ""
                if stop == "refusal" {
                    answer += answer.isEmpty ? "이 질문에는 답할 수 없다고 응답했어요." : "\n\n(응답이 중간에 중단되었어요.)"
                } else if stop == "max_tokens" {
                    answer += "\n\n(답변이 길어서 중간에 잘렸어요.)"
                }
                self.finish(threadID: threadID, answer: answer)
            } catch {
                guard let self else { return }
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled {
                    self.errorText = error.localizedDescription
                    DebugLog.log("send error (\(backend.rawValue)): \(error.localizedDescription.prefix(300))")
                }
                self.finish(threadID: threadID, answer: self.streamingText ?? "")
            }
        }
    }

    func cancelSending() {
        sendTask?.cancel()
        sendTask = nil
    }

    private func finish(threadID: UUID, answer: String) {
        if !answer.isEmpty, let idx = threads.firstIndex(where: { $0.id == threadID }) {
            threads[idx].messages.append(ChatMessage(role: .assistant, text: answer))
            save()
        }
        streamingText = nil
        isSending = false
        sendTask = nil
    }

    // MARK: 저장

    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TailQuestions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("threads.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([TailThread].self, from: data) else { return }
        threads = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(threads) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

enum Prompt {
    static func system(for thread: TailThread) -> String {
        var s = """
        You are Claude. The user is in the middle of a conversation with you in the Claude app and has \
        opened a side panel to ask a "tail question": a follow-up that branches off from one point of that \
        conversation, like a git branch off main. Answer as the same assistant who wrote the conversation \
        below, with full knowledge of it, but focus only on the tail question. The main conversation will \
        continue separately, so do not try to steer it. Reply in the language the user writes in. Keep \
        answers focused; the panel is narrow.
        """
        if !thread.transcript.isEmpty {
            let title = thread.conversationTitle.isEmpty || thread.conversationTitle == "Claude"
                ? "" : " title=\"\(thread.conversationTitle)\""
            s += "\n\n<main_conversation\(title)>\n"
            for block in thread.transcript {
                s += "<turn role=\"\(block.kind.rawValue)\">\n\(block.text)\n</turn>\n"
            }
            s += "</main_conversation>"
        }
        return s
    }

    /// 가지의 첫 질문에 분기 지점(선택한 텍스트 또는 질문)을 붙인다.
    static func firstUserText(for thread: TailThread, question: String) -> String {
        if !thread.selection.isEmpty {
            return """
            <selected_text>
            \(thread.selection)
            </selected_text>

            The text above is the part of the main conversation I highlighted. My question about it:
            \(question)
            """
        }
        if let main = thread.mainQuestion {
            return """
            <branch_point>
            \(main)
            </branch_point>

            I'm branching off from the question above in the main conversation (and your answer to it). My question:
            \(question)
            """
        }
        return question
    }

    /// API 방식: 가지의 대화를 그대로 messages 배열로.
    static func apiMessages(for thread: TailThread) -> [[String: Any]] {
        thread.messages.enumerated().map { i, m in
            let text = (i == 0 && m.role == .user) ? firstUserText(for: thread, question: m.text) : m.text
            return ["role": m.role.rawValue, "content": text]
        }
    }

    /// Claude Code 방식: 매번 새로 실행하므로 가지의 지난 대화를 프롬프트 하나에 담는다.
    static func singlePrompt(for thread: TailThread) -> String {
        let msgs = thread.messages
        guard let last = msgs.last else { return "" }
        if msgs.count == 1 { return firstUserText(for: thread, question: last.text) }

        var s = "<side_thread_so_far>\n"
        for (i, m) in msgs.dropLast().enumerated() {
            let text = (i == 0 && m.role == .user) ? firstUserText(for: thread, question: m.text) : m.text
            s += "<turn role=\"\(m.role.rawValue)\">\n\(text)\n</turn>\n"
        }
        s += "</side_thread_so_far>\n\nContinue the side thread. My next message:\n\(last.text)"
        return s
    }
}
