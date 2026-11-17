import Foundation

/// 설치된 Claude Code CLI(`claude -p`)를 통해 질문한다.
/// Claude Code에 로그인된 구독(Pro/Max) 계정을 그대로 쓰므로 API 키가 필요 없다.
struct ClaudeCodeClient {
    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    /// 설치 후 다시 확인할 수 있도록 매번 찾는다.
    static var binaryPath: String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.npm-global/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        return env
    }

    /// `claude auth status` → 로그인 여부. 확인할 수 없으면 nil.
    static func isLoggedIn() async -> Bool? {
        guard let bin = binaryPath else { return nil }
        return await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["auth", "status"]
            p.environment = environment
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            do { try p.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let loggedIn = obj["loggedIn"] as? Bool {
                return loggedIn
            }
            return p.terminationStatus == 0 ? true : false
        }.value
    }

    /// `claude auth login` 실행 (브라우저가 열려 Claude 계정으로 로그인).
    static func startLogin() -> Process? {
        guard let bin = binaryPath else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["auth", "login"]
        p.environment = environment
        p.standardInput = Pipe()
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        return p
    }

    var binary: String
    var model: String

    private static var workDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TailQuestions/claude-workdir", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// - Returns: stop_reason
    func stream(system: String, prompt: String, onText: @escaping @MainActor (String) -> Void) async throws -> String? {
        let dir = Self.workDir
        let systemFile = dir.appendingPathComponent("system-\(UUID().uuidString).txt")
        try system.write(to: systemFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: systemFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.currentDirectoryURL = dir   // 빈 폴더: 다른 프로젝트의 CLAUDE.md 등을 읽지 않게
        process.arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--system-prompt-file", systemFile.path,
            "--tools", "",                 // 도구 없이 대답만
            "--setting-sources", "",       // 사용자 설정·훅 무시
            "--strict-mcp-config",         // MCP 서버 로드 안 함
            "--no-session-persistence",    // Claude Code 기록에 남기지 않음
            "--model", model,
        ]
        process.environment = Self.environment

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let input = Data(prompt.utf8)
        DispatchQueue.global().async {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }

        return try await withTaskCancellationHandler {
            var stopReason: String?
            var resultError: String?

            for try await line in stdout.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = obj["type"] as? String else { continue }

                if type == "stream_event", let event = obj["event"] as? [String: Any] {
                    switch event["type"] as? String {
                    case "content_block_delta":
                        if let delta = event["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let text = delta["text"] as? String {
                            await onText(text)
                        }
                    case "message_delta":
                        if let delta = event["delta"] as? [String: Any], let r = delta["stop_reason"] as? String {
                            stopReason = r
                        }
                    default:
                        break
                    }
                } else if type == "result", obj["is_error"] as? Bool == true {
                    resultError = (obj["result"] as? String) ?? (obj["subtype"] as? String) ?? "알 수 없는 오류"
                }
            }

            process.waitUntilExit()
            try Task.checkCancellation()

            if let resultError { throw ClaudeError.stream(Self.friendly(resultError)) }
            if process.terminationStatus != 0 {
                let errText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ClaudeError.stream(Self.friendly(errText.isEmpty ? "claude 실행 실패 (\(process.terminationStatus))" : errText))
            }
            return stopReason
        } onCancel: {
            process.terminate()
        }
    }

    private static func friendly(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("login") || lower.contains("not logged in") || lower.contains("authenticat") {
            return "Claude Code에 로그인되어 있지 않아요. 터미널에서 `claude`를 실행해 로그인해 주세요.\n(\(message))"
        }
        if lower.contains("limit") {
            return "구독 사용 한도에 도달했어요. 잠시 후 다시 시도해 주세요.\n(\(message))"
        }
        return message
    }
}
