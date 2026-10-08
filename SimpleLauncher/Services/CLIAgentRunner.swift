import Darwin
import Foundation

struct CLIAgentError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }
}

struct CLIStreamUpdate: Sendable {
    var answer: String?
    var status: String?
    var error: String?
}

/// Finds `codex`, `claude`, and `cursor-agent` for a GUI app whose PATH is not the user's shell PATH.
enum CLIAgentLocator {
    static func resolve(provider: AIProvider, customPath: String) -> Result<String, CLIAgentError> {
        let override = expand(customPath)
        if !override.isEmpty {
            if FileManager.default.isExecutableFile(atPath: override) {
                return .success(override)
            }
            return .failure(CLIAgentError(message: "Couldn't find \(provider.title) at \(override)."))
        }
        if let known = knownExecutable(provider: provider) {
            return .success(known)
        }
        if let which = shellWhich(provider: provider) {
            return .success(which)
        }
        let name = provider.commandName
        return .failure(CLIAgentError(
            message: "Couldn't find \(provider.title) (`\(name)`). Install the CLI, or set its path in Settings."
        ))
    }

    /// Settings hint. Checks a custom path and common install locations, and does not spawn a shell.
    static func preview(provider: AIProvider, customPath: String) -> String? {
        let override = expand(customPath)
        if !override.isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        return knownExecutable(provider: provider)
    }

    static func customPathProblem(provider: AIProvider, customPath: String) -> String? {
        let override = expand(customPath)
        guard !override.isEmpty else { return nil }
        guard FileManager.default.isExecutableFile(atPath: override) else {
            return "No executable at \(override)."
        }
        return nil
    }

    private static func expand(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).expandingTildeInPath
    }

    private static func knownExecutable(provider: AIProvider) -> String? {
        let name = provider.commandName
        guard !name.isEmpty else { return nil }
        let home = NSHomeDirectory()
        let directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.cargo/bin",
            "\(home)/.cursor/bin",
            "\(home)/.opencode/bin",
        ]
        for directory in directories {
            let path = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // The Cursor installer also symlinks the same binary as `agent`.
        if provider == .cursor {
            let agent = "\(home)/.local/bin/agent"
            if FileManager.default.isExecutableFile(atPath: agent) {
                return agent
            }
        }
        return nil
    }

    private static let whichLock = NSLock()
    private static var whichCache: [String: String] = [:]

    private static func shellWhich(provider: AIProvider) -> String? {
        let name = provider.commandName
        guard !name.isEmpty else { return nil }
        whichLock.lock()
        if let cached = whichCache[name] {
            whichLock.unlock()
            return cached.isEmpty ? nil : cached
        }
        whichLock.unlock()

        let found = loginWhich(name)
        whichLock.lock()
        whichCache[name] = found ?? ""
        whichLock.unlock()
        return found
    }

    /// Login shell, then interactive, so PATH from `.zprofile` or `.zshrc` is visible.
    private static func loginWhich(_ name: String) -> String? {
        let script = "command -v \(name)"
        for flag in ["-lc", "-lic"] {
            guard let output = runZsh(arguments: [flag, script], timeout: 2) else { continue }
            let lines = output.split(whereSeparator: \.isNewline).map(String.init)
            for line in lines.reversed() {
                let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { continue }
                return path
            }
        }
        return nil
    }

    private static func runZsh(arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

/// Runs one non-interactive CLI turn and streams the assistant text into `onUpdate`.
enum CLIAgentSession {
    static func run(
        provider: AIProvider,
        executable: String,
        model: String,
        prompt: String,
        autoMode: Bool,
        onUpdate: @escaping @Sendable (CLIStreamUpdate) async -> Void
    ) async throws {
        let workspace = workspaceDirectory(autoMode: autoMode)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(
            provider: provider,
            model: model,
            prompt: prompt,
            workspace: workspace,
            autoMode: autoMode
        )
        process.currentDirectoryURL = workspace
        process.environment = environment(executable: executable)
        process.qualityOfService = .userInitiated
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let box = CLIProcessBox(process: process)
        let lines = AsyncStream<String> { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                let handle = stdout.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let range = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                        if let line = String(data: lineData, encoding: .utf8) {
                            continuation.yield(line)
                        }
                    }
                }
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
                continuation.finish()
            }
            DispatchQueue.global(qos: .utility).async {
                var data = Data()
                let handle = stderr.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    data.append(chunk)
                    if data.count > 32_000 {
                        data = data.suffix(16_000)
                    }
                }
                box.setStderr(data)
            }
        }

        do {
            try process.run()
        } catch {
            throw CLIAgentError(message: "Couldn't start \(provider.title): \(error.localizedDescription)")
        }

        let parser = CLIEventParser(provider: provider)
        var latestAnswer = ""
        var sawError = false

        try await withTaskCancellationHandler {
            for await line in lines {
                try Task.checkCancellation()
                let update = parser.consume(line)
                if let answer = update.answer {
                    latestAnswer = answer
                }
                if let error = update.error, !error.isEmpty {
                    sawError = true
                }
                if update.answer != nil || update.status != nil || update.error != nil {
                    await onUpdate(update)
                }
            }
            try Task.checkCancellation()
            if process.isRunning {
                process.waitUntilExit()
            }
            await box.waitForStderr()
        } onCancel: {
            box.stop()
        }

        let status = process.terminationStatus
        if !sawError && latestAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && status != 0 {
            let fallback = "\(provider.title) exited with status \(status)."
            await onUpdate(CLIStreamUpdate(error: box.stderrMessage(fallback: fallback)))
        }
    }

    /// Read-only questions stay in an empty directory. Auto mode uses the home folder so edits have somewhere to land.
    private static func workspaceDirectory(autoMode: Bool) -> URL {
        if autoMode {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("SimpleLauncher/cli-workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func assistantInstruction(autoMode: Bool) -> String {
        if autoMode {
            return """
            You are answering one question from a macOS launcher. \
            Reply directly and concisely in markdown. \
            You may edit files and run commands when the question needs it.
            """
        }
        return """
        You are answering one question from a macOS launcher. \
        Reply directly and concisely in markdown. \
        Do not edit or create files.
        """
    }

    private static func arguments(
        provider: AIProvider,
        model: String,
        prompt: String,
        workspace: URL,
        autoMode: Bool
    ) -> [String] {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = workspace.path
        let instruction = assistantInstruction(autoMode: autoMode)
        switch provider {
        case .api:
            return []
        case .codex:
            var args = [
                "exec", "--json", "--color", "never",
                "--ephemeral", "--skip-git-repo-check",
                "--cd", directory,
            ]
            if autoMode {
                // Implies the workspace-write sandbox. Codex rejects combining it with --sandbox.
                args.append("--approve-for-me")
            } else {
                args.append(contentsOf: ["--sandbox", "read-only"])
            }
            if !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: ["--", wrappedPrompt(prompt, instruction: instruction)])
            return args
        case .claude:
            var args = [
                "--print",
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--no-session-persistence",
                "--permission-mode", autoMode ? "auto" : "plan",
                "--permission-prompts", "none",
                "--no-chrome",
                "--append-system-prompt", instruction,
            ]
            if !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: ["--", prompt])
            return args
        case .cursor:
            var args = [
                "--print",
                "--output-format", "stream-json",
                "--stream-partial-output",
                "--trust",
                "--workspace", directory,
            ]
            if autoMode {
                args.append(contentsOf: ["--force", "--sandbox", "disabled"])
            } else {
                args.append(contentsOf: ["--mode", "ask"])
            }
            if !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: ["--", wrappedPrompt(prompt, instruction: instruction)])
            return args
        case .opencode:
            var args = [
                "run", "--format", "json",
                "--dir", directory,
            ]
            if autoMode {
                args.append("--auto")
            } else {
                args.append(contentsOf: ["--agent", "plan"])
            }
            if !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: ["--", wrappedPrompt(prompt, instruction: instruction)])
            return args
        }
    }

    private static func wrappedPrompt(_ prompt: String, instruction: String) -> String {
        """
        \(instruction)

        \(prompt)
        """
    }

    private static func environment(executable: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let binDir = (executable as NSString).deletingLastPathComponent
        let parts = [
            binDir,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.cargo/bin",
            "\(home)/.opencode/bin",
            env["PATH"] ?? "",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var seen = Set<String>()
        let merged = parts
            .flatMap { $0.split(separator: ":").map(String.init) }
            .filter { part in
                !part.isEmpty && seen.insert(part).inserted
            }
        env["PATH"] = merged.joined(separator: ":")
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["PAGER"] = "cat"
        env["GIT_PAGER"] = "cat"
        return env
    }
}

private final class CLIProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var stopped = false
    private var stderr = Data()
    private var stderrFinished = false
    private var stderrWaiters: [CheckedContinuation<Void, Never>] = []

    init(process: Process) {
        self.process = process
    }

    func stop() {
        lock.lock()
        let already = stopped
        stopped = true
        lock.unlock()
        guard !already, process.isRunning else { return }

        let pid = process.processIdentifier
        if pid > 0 {
            kill(pid, SIGINT)
            let children = Process()
            children.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            children.arguments = ["-INT", "-P", String(pid)]
            children.standardOutput = FileHandle.nullDevice
            children.standardError = FileHandle.nullDevice
            children.standardInput = FileHandle.nullDevice
            try? children.run()
        }
        let process = self.process
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.5) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    func setStderr(_ data: Data) {
        lock.lock()
        stderr = data
        stderrFinished = true
        let waiters = stderrWaiters
        stderrWaiters.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForStderr() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if stderrFinished {
                lock.unlock()
                continuation.resume()
                return
            }
            stderrWaiters.append(continuation)
            lock.unlock()
        }
    }

    func stderrMessage(fallback: String) -> String {
        lock.lock()
        let data = stderr
        lock.unlock()
        let raw = String(data: data, encoding: .utf8) ?? ""
        let stripped = raw.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        let lines = stripped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return fallback }
        var tail = lines.suffix(6).joined(separator: "\n")
        if tail.count > 500 {
            tail = String(tail.suffix(500))
        }
        return tail
    }
}

private final class CLIEventParser {
    private let provider: AIProvider
    private var codex = CodexEventParser()
    private var claude = ClaudeEventParser()
    private var cursor = CursorEventParser()
    private var opencode = OpenCodeEventParser()

    init(provider: AIProvider) {
        self.provider = provider
    }

    func consume(_ line: String) -> CLIStreamUpdate {
        switch provider {
        case .api:
            return CLIStreamUpdate()
        case .codex:
            return codex.consume(line)
        case .claude:
            return claude.consume(line)
        case .cursor:
            return cursor.consume(line)
        case .opencode:
            return opencode.consume(line)
        }
    }
}

private struct CodexEventParser {
    private var messages: [String: String] = [:]
    private var order: [String] = []
    private var toolActive = false

    mutating func consume(_ line: String) -> CLIStreamUpdate {
        guard let json = CLIJSON.object(from: line) else { return CLIStreamUpdate() }
        switch json["type"] as? String {
        case "error":
            let message = (json["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CLIStreamUpdate(error: message.isEmpty ? "Codex error" : message)
        case "turn.failed":
            return CLIStreamUpdate(error: Self.failureMessage(json))
        case "item.started", "item.updated", "item.completed":
            guard let item = json["item"] as? [String: Any] else { return CLIStreamUpdate() }
            return consumeItem(item)
        default:
            return CLIStreamUpdate()
        }
    }

    private mutating func consumeItem(_ item: [String: Any]) -> CLIStreamUpdate {
        let type = item["type"] as? String ?? ""
        if type == "agent_message" {
            let id = (item["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "message"
            let text = (item["text"] as? String) ?? (item["message"] as? String) ?? ""
            if messages[id] == nil {
                order.append(id)
            }
            messages[id] = text
            let answer = order.compactMap { messages[$0] }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            let status = toolActive ? "Thinking…" : nil
            toolActive = false
            return CLIStreamUpdate(answer: answer, status: status)
        }
        guard let status = Self.status(for: type) else { return CLIStreamUpdate() }
        toolActive = true
        return CLIStreamUpdate(status: status)
    }

    private static func status(for type: String) -> String? {
        switch type {
        case "web_search":
            return "Searching…"
        case "command_execution":
            return "Running…"
        case "mcp_tool_call", "file_change", "todo_list":
            return "Working…"
        default:
            return nil
        }
    }

    private static func failureMessage(_ json: [String: Any]) -> String {
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
        }
        return "Codex turn failed."
    }
}

private struct ClaudeEventParser {
    private var answer = ""
    private var sawPartial = false
    private var toolActive = false

    mutating func consume(_ line: String) -> CLIStreamUpdate {
        guard let json = CLIJSON.object(from: line) else { return CLIStreamUpdate() }
        switch json["type"] as? String {
        case "stream_event":
            return consumeStreamEvent(json)
        case "assistant":
            return consumeAssistant(json)
        case "result":
            return consumeResult(json)
        default:
            if let delta = CLIJSON.textDelta(in: json) {
                return appendText(delta)
            }
            return CLIStreamUpdate()
        }
    }

    private mutating func consumeStreamEvent(_ json: [String: Any]) -> CLIStreamUpdate {
        if let name = CLIJSON.toolName(in: json) {
            toolActive = true
            return CLIStreamUpdate(status: CLIJSON.status(forToolName: name))
        }
        if let delta = CLIJSON.textDelta(in: json), !delta.isEmpty {
            return appendText(delta)
        }
        return CLIStreamUpdate()
    }

    private mutating func consumeAssistant(_ json: [String: Any]) -> CLIStreamUpdate {
        var status: String?
        if let message = json["message"] as? [String: Any],
           let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                guard (block["type"] as? String) == "tool_use",
                      let name = block["name"] as? String, !name.isEmpty else { continue }
                toolActive = true
                status = CLIJSON.status(forToolName: name)
            }
        }
        if sawPartial {
            sawPartial = false
            return CLIStreamUpdate(status: status)
        }
        let text = CLIJSON.assistantText(json)
        guard !text.isEmpty else { return CLIStreamUpdate(status: status) }
        if !answer.isEmpty {
            answer += "\n\n"
        }
        answer += text
        let thinking = toolActive ? "Thinking…" : nil
        toolActive = false
        return CLIStreamUpdate(answer: answer, status: status ?? thinking)
    }

    private mutating func consumeResult(_ json: [String: Any]) -> CLIStreamUpdate {
        let isError = (json["is_error"] as? Bool) ?? ((json["subtype"] as? String)?.hasPrefix("error") ?? false)
        let result = (json["result"] as? String) ?? ""
        if isError {
            let message = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return CLIStreamUpdate(error: message.isEmpty ? "Claude failed." : message)
        }
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.isEmpty {
            answer = result
            return CLIStreamUpdate(answer: answer)
        }
        return CLIStreamUpdate()
    }

    private mutating func appendText(_ delta: String) -> CLIStreamUpdate {
        sawPartial = true
        answer += delta
        let status = toolActive ? "Thinking…" : nil
        toolActive = false
        return CLIStreamUpdate(answer: answer, status: status)
    }
}

private struct OpenCodeEventParser {
    private var messages: [String: String] = [:]
    private var order: [String] = []
    private var toolActive = false

    mutating func consume(_ line: String) -> CLIStreamUpdate {
        guard let json = CLIJSON.object(from: line) else { return CLIStreamUpdate() }
        switch json["type"] as? String {
        case "error":
            return CLIStreamUpdate(error: Self.failureMessage(json))
        case "text":
            guard let part = json["part"] as? [String: Any] else { return CLIStreamUpdate() }
            let id = (part["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "message"
            let text = part["text"] as? String ?? ""
            if messages[id] == nil {
                order.append(id)
            }
            messages[id] = text
            let answer = order.compactMap { messages[$0] }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            let status = toolActive ? "Thinking…" : nil
            toolActive = false
            return CLIStreamUpdate(answer: answer, status: status)
        case "tool_use":
            let tool = (json["part"] as? [String: Any])?["tool"] as? String ?? ""
            toolActive = true
            return CLIStreamUpdate(status: CLIJSON.status(forToolName: tool.isEmpty ? "tool" : tool))
        default:
            return CLIStreamUpdate()
        }
    }

    private static func failureMessage(_ json: [String: Any]) -> String {
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = json["error"] as? [String: Any] {
            if let data = error["data"] as? [String: Any],
               let message = data["message"] as? String, !message.isEmpty {
                return message
            }
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let name = error["name"] as? String, !name.isEmpty {
                return name
            }
        }
        return "OpenCode failed."
    }
}

private struct CursorEventParser {
    private var answer = ""
    private var toolActive = false

    mutating func consume(_ line: String) -> CLIStreamUpdate {
        guard let json = CLIJSON.object(from: line) else { return CLIStreamUpdate() }
        switch json["type"] as? String {
        case "assistant":
            // Partial streaming emits three assistant events; only the delta has new text.
            let isDelta = CLIJSON.isPresent(json["timestamp_ms"]) && !CLIJSON.isPresent(json["model_call_id"])
            guard isDelta else { return CLIStreamUpdate() }
            let text = CLIJSON.assistantText(json)
            guard !text.isEmpty else { return CLIStreamUpdate() }
            answer += text
            let status = toolActive ? "Thinking…" : nil
            toolActive = false
            return CLIStreamUpdate(answer: answer, status: status)
        case "tool_call":
            guard (json["subtype"] as? String) == "started" else { return CLIStreamUpdate() }
            toolActive = true
            return CLIStreamUpdate(status: CLIJSON.cursorToolStatus(json))
        case "result":
            let isError = (json["is_error"] as? Bool) ?? false
            let result = (json["result"] as? String) ?? ""
            if isError {
                let message = result.trimmingCharacters(in: .whitespacesAndNewlines)
                return CLIStreamUpdate(error: message.isEmpty ? "Cursor Agent failed." : message)
            }
            if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.isEmpty {
                answer = result
                return CLIStreamUpdate(answer: answer)
            }
            return CLIStreamUpdate()
        default:
            return CLIStreamUpdate()
        }
    }
}

private enum CLIJSON {
    static func object(from line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func isPresent(_ value: Any?) -> Bool {
        guard let value = value, !(value is NSNull) else { return false }
        return true
    }

    static func assistantText(_ json: [String: Any]) -> String {
        guard let message = json["message"] as? [String: Any] else { return "" }
        if let content = message["content"] as? String { return content }
        guard let blocks = message["content"] as? [[String: Any]] else { return "" }
        return blocks.compactMap { block in
            let type = block["type"] as? String
            guard type == nil || type == "text" else { return nil }
            return block["text"] as? String
        }.joined()
    }

    static func textDelta(in json: [String: Any]) -> String? {
        let event = (json["event"] as? [String: Any]) ?? json
        guard (event["type"] as? String) == "content_block_delta",
              let delta = event["delta"] as? [String: Any],
              (delta["type"] as? String) == "text_delta" else { return nil }
        return delta["text"] as? String
    }

    static func toolName(in json: [String: Any]) -> String? {
        let event = (json["event"] as? [String: Any]) ?? json
        guard (event["type"] as? String) == "content_block_start",
              let block = event["content_block"] as? [String: Any],
              (block["type"] as? String) == "tool_use" else { return nil }
        let name = block["name"] as? String
        return name?.isEmpty == false ? name : nil
    }

    static func status(forToolName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("search") { return "Searching…" }
        if lower.contains("fetch") || lower.contains("web") { return "Fetching…" }
        if lower == "bash" || lower.contains("shell") || lower.contains("command") { return "Running…" }
        return "Working…"
    }

    static func cursorToolStatus(_ json: [String: Any]) -> String {
        guard let tool = json["tool_call"] as? [String: Any] else { return "Working…" }
        let joined = tool.keys.joined(separator: " ").lowercased()
        if joined.contains("search") { return "Searching…" }
        if joined.contains("fetch") || joined.contains("web") { return "Fetching…" }
        if let function = tool["function"] as? [String: Any], let name = function["name"] as? String {
            return status(forToolName: name)
        }
        return "Working…"
    }
}
