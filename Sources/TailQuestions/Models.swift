import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
}

/// 메인 대화에서 읽어온 한 덩어리(내 질문 또는 Claude 답변).
struct TranscriptBlock: Codable, Equatable {
    enum Kind: String, Codable { case user, assistant, unknown }
    var kind: Kind
    var text: String
}

struct Conversation {
    var title: String
    var blocks: [TranscriptBlock]

    /// 대화를 구분하는 키. Claude 창 제목은 늘 "Claude"일 수 있어서 첫 질문을 기준으로 삼는다.
    var key: String {
        let first = blocks.first(where: { $0.kind == .user }) ?? blocks.first
        return String(TextUtil.normalize(first?.text ?? "").prefix(80))
    }

    var displayTitle: String {
        if !title.isEmpty, title != "Claude" { return title }
        let first = blocks.first(where: { $0.kind == .user })?.text ?? "대화"
        return String(TextUtil.normalize(first).prefix(40))
    }

    /// main 브랜치의 커밋들 = 내 질문과 그에 대한 답변 한 쌍씩.
    struct Turn: Identifiable {
        var id: Int
        var question: String
        var answer: String?
    }

    var turns: [Turn] {
        var result: [Turn] = []
        for (i, b) in blocks.enumerated() where b.kind == .user {
            let next = blocks.indices.contains(i + 1) && blocks[i + 1].kind == .assistant ? blocks[i + 1].text : nil
            result.append(Turn(id: result.count, question: b.text, answer: next))
        }
        return result
    }
}

/// 꼬리질문 하나 = 원래 대화의 한 지점에서 뻗어 나온 가지 하나.
struct TailThread: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var conversationTitle: String
    var conversationKey: String?
    var mainQuestion: String?
    var selection: String
    var transcript: [TranscriptBlock]
    var messages: [ChatMessage] = []

    var conversation: Conversation { Conversation(title: conversationTitle, blocks: transcript) }

    var displayTitle: String {
        let firstQuestion = messages.first(where: { $0.role == .user })?.text
        let base = firstQuestion ?? selection
        let oneLine = base.replacingOccurrences(of: "\n", with: " ")
        return oneLine.isEmpty ? "새 꼬리질문" : String(oneLine.prefix(40))
    }
}

enum TextUtil {
    static func normalize(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func sameText(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return normalize(a).prefix(80) == normalize(b).prefix(80)
    }

    /// 선택한 텍스트가 들어 있는 블록을 찾고, 그 블록 이전의 가장 가까운 '내 질문'을 돌려준다.
    static func findMainQuestion(selection: String, in blocks: [TranscriptBlock]) -> String? {
        let needle = String(normalize(selection).prefix(40))
        guard !needle.isEmpty else { return nil }
        guard let idx = blocks.firstIndex(where: { normalize($0.text).contains(needle) }) else {
            return blocks.last(where: { $0.kind == .user })?.text
        }
        return blocks[...idx].last(where: { $0.kind == .user })?.text
    }
}
