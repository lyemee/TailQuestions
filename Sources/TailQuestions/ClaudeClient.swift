import Foundation

enum ClaudeError: LocalizedError {
    case http(Int, String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            if code == 401 { return "API 키가 올바르지 않아요. 설정에서 다시 입력해 주세요." }
            if code == 429 { return "요청이 너무 많아요. 잠시 후 다시 시도해 주세요." }
            return "API 오류 (\(code)): \(body)"
        case .stream(let msg):
            return "응답 중 오류: \(msg)"
        }
    }
}

/// Anthropic Messages API를 스트리밍으로 호출한다 (Swift 공식 SDK가 없어 REST 직접 호출).
struct ClaudeClient {
    static let models: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]

    var apiKey: String
    var model: String

    /// - Returns: stop_reason
    func stream(system: String, messages: [[String: Any]], onText: @escaping @MainActor (String) -> Void) async throws -> String? {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "stream": true,
            "system": system,
            "messages": messages,
            // 대화 전체(system)를 매 턴 다시 보내므로 캐싱으로 비용을 줄인다.
            "cache_control": ["type": "ephemeral"],
            "output_config": ["effort": "medium"],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")

        // 안전 필터가 거절하면 서버가 자동으로 다른 모델로 이어서 답하게 한다 (Haiku는 미지원).
        if !model.contains("haiku") {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 600

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw ClaudeError.http(status, Self.errorMessage(from: data))
        }

        var stopReason: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String {
                    await onText(text)
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }
            case "error":
                let msg = (event["error"] as? [String: Any])?["message"] as? String ?? "알 수 없는 오류"
                throw ClaudeError.stream(msg)
            default:
                break
            }
        }
        return stopReason
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
