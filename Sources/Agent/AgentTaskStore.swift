import AppKit
import Darwin

struct AgentPlanStep: Codable {
    let content: String
    let status: String
}

struct AgentJob: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var prompt: String
    var workspace: String
    var endpoint: String
    var model: String
    var status = "running"
    var result = ""
    var logs: [String] = []
    var activity: [String]?
    var reply: String?
    var plan: [AgentPlanStep]?
    var engine: String?
    @MainActor var displayResult: String {
        if status == "failed" && result.hasPrefix("GraphRecursionError:") {
            return ChatText.pick("这次查看的范围太大，已达到执行步数上限。请缩小范围后再试，例如先只读 README 和入口文件。",
                                 "This task reached its step limit before finishing. Try a narrower scope, such as the README and entry points.")
        }
        return result
    }
}

struct AgentApproval: Identifiable {
    let id = UUID()
    let name: String
    let arguments: String
}

@MainActor
final class AgentTaskStore: ObservableObject {
    static let shared = AgentTaskStore()
    @Published private(set) var jobs: [AgentJob] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var approvals: [AgentApproval] = []
    @Published private(set) var runtimeReady = false
    @Published private(set) var installing = false
    @Published private(set) var checking = false
    @Published private(set) var setupStatus: String?
    private var installationTask: Task<Void, Never>?
    @Published var error: String?
    @Published var workspace: String {
        didSet { UserDefaults.standard.set(workspace, forKey: "agent.workspace") }
    }
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var receivedTerminalEvent = false
    private var archiveFailed = false
    private var currentReplyID = ""
    private var saveTask: Task<Void, Never>?
    private let support: URL
    private var archive: URL { support.appendingPathComponent("tasks.json") }
    var isBusy: Bool { activeID != nil }
    private var runtimeBase: URL { support.appendingPathComponent("AgentRuntime") }
    var managedRuntime: ManagedAgentRuntime { ManagedAgentRuntime(base: runtimeBase, architecture: ManagedAgentRuntime.hostArchitecture) }
    var python: URL { managedRuntime.ready ? managedRuntime.python : runtimeBase.appendingPathComponent(".venv/bin/python") }
    private var workerEnvironment: [String: String] {
        var environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
                           "PYTHONUNBUFFERED": "1", "PYTHONNOUSERSITE": "1", "LANGSMITH_TRACING": "false"]
        if managedRuntime.ready { environment["DAFEIYU_DSH_BIN"] = managedRuntime.harness.path }
        return environment
    }
    var runtime: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("AgentRuntime")
        if let bundled, FileManager.default.fileExists(atPath: bundled.appendingPathComponent("worker.py").path) { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("AgentRuntime")
    }

    init(support: URL? = nil) {
        self.support = support ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BaifanYu")
        workspace = UserDefaults.standard.string(forKey: "agent.workspace") ?? ""
        do {
            if FileManager.default.fileExists(atPath: archive.path) {
                jobs = try JSONDecoder().decode([AgentJob].self, from: Data(contentsOf: archive))
                for i in jobs.indices where jobs[i].status == "running" { jobs[i].status = "interrupted" }
            }
        } catch {
            archiveFailed = true
            self.error = ChatText.pick("任务记录无法读取，已保留原文件。", "Task history could not be read; original file preserved.")
        }
    }

    private func persist() {
        saveTask?.cancel()
        saveTask = nil
        guard !archiveFailed else { return }
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try JSONEncoder().encode(jobs).write(to: archive, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        } catch {
            self.error = ChatText.pick("无法保存任务记录：", "Cannot save task history: ") + error.localizedDescription
        }
    }

    private func persistSoon() {
        guard saveTask == nil else { return }
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            saveTask = nil
            persist()
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { workspace = url.resolvingSymlinksInPath().path }
    }

    func checkRuntime() {
        guard !checking, !installing else { return }
        checking = true
        let executable = python
        let worker = runtime.appendingPathComponent("worker.py")
        let environment = workerEnvironment
        Task {
            let ok = await Task.detached { () -> Bool in
                guard FileManager.default.isExecutableFile(atPath: executable.path) else { return false }
                let process = Process()
                process.executableURL = executable
                process.arguments = [worker.path, "--check"]
                process.environment = environment
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
                catch { return false }
            }.value
            runtimeReady = ok
            checking = false
        }
    }

    func installRuntime() {
        guard !installing, !checking, !isBusy else { return }
        installing = true
        error = nil
        setupStatus = ChatText.pick("正在准备下载…", "Preparing download…")
        let installer = AgentRuntimeInstaller(base: runtimeBase)
        installationTask = Task {
            defer { installing = false; setupStatus = nil; installationTask = nil }
            do {
                _ = try await installer.install { [weak self] phase in
                    Task { @MainActor in
                        guard let self, self.installing else { return }
                        self.setupStatus = ChatText.pick(phase.chinese, phase.english)
                    }
                }
                try Task.checkCancellation()
                runtimeReady = managedRuntime.ready
            } catch {
                if !Task.isCancelled {
                    self.error = ChatText.pick("准备失败，点击「启用工作能力」可重试：", "Setup failed. Choose Enable tasks to retry: ") + error.localizedDescription
                }
                runtimeReady = managedRuntime.ready
            }
        }
    }

    func cancelRuntimeInstallation() { installationTask?.cancel() }

    @discardableResult
    func submit(_ prompt: String) -> Bool {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !archiveFailed, runtimeReady, !prompt.isEmpty else { return false }
        guard prompt.count <= 8000 else {
            error = ChatText.pick("任务描述最多 8,000 字符。", "Task descriptions are limited to 8,000 characters.")
            return false
        }
        let chat = ChatStore.shared
        let job = AgentJob(prompt: prompt, workspace: workspace, endpoint: chat.endpoint, model: chat.model, engine: "harness")
        return launch(job, resume: false)
    }

    func resume(_ job: AgentJob) {
        guard !isBusy, job.status == "approval", runtimeReady else { return }
        _ = launch(job, resume: true)
    }

    private func launch(_ job: AgentJob, resume: Bool) -> Bool {
        do {
            guard !job.model.isEmpty else {
                throw ChatFailure.message(ChatText.pick("请先在聊天连接设置中保存模型。", "Save a model in chat connection settings first."))
            }
            let endpoint = try ChatStore.validatedURL(job.endpoint)
            guard endpoint.path.hasSuffix("/chat/completions") else {
                throw ChatFailure.message(ChatText.pick("Agent 接口地址须以 /chat/completions 结尾。", "Agent endpoint must end in /chat/completions."))
            }
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: job.workspace, isDirectory: &directory), directory.boolValue else {
                throw ChatFailure.message(ChatText.pick("请先选择可访问的工作目录。", "Choose an accessible workspace first."))
            }
            let key = try ChatKeychain.read(endpoint: job.endpoint)
            let state = support.appendingPathComponent("AgentTasks/\(job.id.uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let payload: [String: Any] = ["id": job.id.uuidString, "prompt": job.prompt,
                                         "workspace": job.workspace, "endpoint": job.endpoint,
                                         "model": job.model, "key": key, "state_dir": state.path, "resume": resume,
                                         "engine": job.engine ?? "deepagents"]
            var request = try JSONSerialization.data(withJSONObject: payload)
            request.append(0x0a)
            let worker = Process()
            let stdin = Pipe(), stdout = Pipe()
            worker.executableURL = job.engine == "harness" ? python : runtimeBase.appendingPathComponent(".venv/bin/python")
            worker.arguments = [runtime.appendingPathComponent("worker.py").path]
            worker.standardInput = stdin
            worker.standardOutput = stdout
            worker.standardError = FileHandle.nullDevice
            // Credentials are supplied through stdin, never command-line arguments or environment.
            worker.environment = workerEnvironment
            try worker.run()
            process = worker
            input = stdin.fileHandleForWriting
            activeID = job.id
            approvals = []
            buffer = Data()
            receivedTerminalEvent = false
            currentReplyID = ""
            error = nil
            if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index].status = "running" }
            else { jobs.insert(job, at: 0) }
            persist()
            // One reader preserves JSONL ordering, including the final event before process exit.
            Task.detached { [weak self] in
                while true {
                    let data = stdout.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    await self?.consume(data, jobID: job.id)
                }
                worker.waitUntilExit()
                await self?.finished(jobID: job.id, exitCode: worker.terminationStatus)
            }
            do { try input?.write(contentsOf: request) }
            catch { stop(); throw error }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func consume(_ data: Data, jobID: UUID) {
        guard activeID == jobID, let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].status != "cancelled" else { return }
        buffer.append(data)
        guard buffer.count <= 2_000_000 else {
            error = ChatText.pick("Agent 返回的数据过大，任务已停止。", "Agent output exceeded the limit; task stopped.")
            stop()
            return
        }
        var important = false
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            let text = event["text"] as? String ?? ""
            if ["status", "approval", "done", "error"].contains(type) { important = true }
            switch type {
            case "reply_delta":
                let id = event["id"] as? String ?? "reply"
                if currentReplyID != id { currentReplyID = id; jobs[index].reply = "" }
                jobs[index].reply = String(((jobs[index].reply ?? "") + text).prefix(100_000))
            case "progress":
                if event["phase"] as? String == "summarizing" {
                    if jobs[index].activity == nil { jobs[index].activity = [] }
                    jobs[index].activity?.append(ChatText.pick("正在整理已有发现…", "Summarizing the findings so far…"))
                } else if event["phase"] as? String == "reviewing" {
                    if jobs[index].activity == nil { jobs[index].activity = [] }
                    jobs[index].activity?.append(ChatText.pick("正在整理这一步的结果…", "Reviewing the result of this step…"))
                }
            case "tool":
                let name = event["name"] as? String ?? ""
                let target = event["target"] as? String ?? ""
                let activity = Self.toolActivity(name, target: target)
                if jobs[index].activity == nil { jobs[index].activity = [] }
                jobs[index].activity?.append(activity)
                if (jobs[index].activity?.count ?? 0) > 30 { jobs[index].activity?.removeFirst() }
                jobs[index].reply = nil
            case "plan":
                if let steps = event["steps"], let data = try? JSONSerialization.data(withJSONObject: steps) {
                    jobs[index].plan = try? JSONDecoder().decode([AgentPlanStep].self, from: data)
                }
            case "log":
                jobs[index].logs.append(String(text.prefix(6000)))
                if jobs[index].logs.count > 200 { jobs[index].logs.removeFirst() }
            case "status": jobs[index].status = "running"
            case "approval":
                approvals = (event["actions"] as? [[String: Any]] ?? []).compactMap { action in
                    guard let name = action["name"] as? String,
                          let args = action["arguments"],
                          let encoded = try? JSONSerialization.data(withJSONObject: args, options: [.prettyPrinted, .sortedKeys]),
                          let string = String(data: encoded, encoding: .utf8) else { return nil }
                    return AgentApproval(name: name, arguments: string)
                }
                jobs[index].status = "approval"
            case "done", "error":
                receivedTerminalEvent = true
                jobs[index].status = type == "done" ? "completed" : "failed"
                jobs[index].result = event["code"] as? String == "step_limit"
                    ? ChatText.pick("已达到本次任务的执行步数上限，请缩小范围后重试。", "The task reached its step limit. Please try a narrower scope.")
                    : String(text.prefix(100_000))
                approvals = []
            default: break
            }
        }
        if important { persist() } else { persistSoon() }
    }

    static func toolActivity(_ name: String, target: String) -> String {
        let detail = target.isEmpty ? "" : " · " + String(target.prefix(100))
        switch name {
        case "workspace_list", "glob", "grep", "working_directory": return ChatText.pick("正在查看文件夹", "Looking through the folder") + detail
        case "workspace_read", "read", "read_image": return ChatText.pick("正在阅读文件", "Reading a file") + detail
        case "workspace_write", "write", "edit": return ChatText.pick("准备修改文件", "Preparing a file change") + detail
        case "run_command", "bash", "workflow": return ChatText.pick("准备运行命令", "Preparing a command")
        case "write_todos", "todo_write": return ChatText.pick("正在安排工作步骤", "Planning the steps")
        default: return ChatText.pick("正在处理任务", "Working on the task")
        }
    }

    func decide(approve: Bool) {
        guard let id = activeID, !approvals.isEmpty else { return }
        do {
            var data = try JSONSerialization.data(withJSONObject: ["type": "decision", "approved": approve])
            data.append(0x0a)
            try input?.write(contentsOf: data)
            approvals = []
            if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index].status = "running" }
            persist()
        } catch { self.error = error.localizedDescription; stop() }
    }

    func stop() {
        guard let id = activeID else { return }
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            guard !["completed", "failed"].contains(jobs[index].status) else { return }
            jobs[index].status = "cancelled"
        }
        approvals = []
        try? input?.close()
        process?.terminate()
        let worker = process
        Task {
            try? await Task.sleep(for: .seconds(3))
            if activeID == id, let worker, worker.isRunning { kill(worker.processIdentifier, SIGKILL) }
        }
        persist()
    }

    private func finished(jobID: UUID, exitCode: Int32) {
        guard activeID == jobID else { return }
        if let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].status != "cancelled", !receivedTerminalEvent {
            jobs[index].status = "failed"
            jobs[index].result = ChatText.pick("Agent 后台意外退出（\(exitCode)）。请检查运行环境。", "Agent exited unexpectedly (\(exitCode)). Check the runtime.")
        }
        try? input?.close()
        input = nil
        process = nil
        activeID = nil
        approvals = []
        buffer = Data()
        persist()
    }

    func delete(_ job: AgentJob) {
        guard job.id != activeID else { return }
        jobs.removeAll { $0.id == job.id }
        try? FileManager.default.removeItem(at: support.appendingPathComponent("AgentTasks/\(job.id.uuidString)"))
        persist()
    }

    static func statusText(_ status: String) -> String {
        switch status {
        case "running": return ChatText.pick("执行中", "Running")
        case "approval": return ChatText.pick("等待确认", "Needs approval")
        case "completed": return ChatText.pick("已完成", "Completed")
        case "cancelled": return ChatText.pick("已停止", "Stopped")
        case "interrupted": return ChatText.pick("上次运行中断", "Interrupted")
        default: return ChatText.pick("失败", "Failed")
        }
    }
}
