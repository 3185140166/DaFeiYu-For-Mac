import AppKit

// Isolated connection and credential stubs: never touch the user's chat settings or Keychain.
@MainActor enum ChatText {
    static func pick(_ chinese: String, _ english: String) -> String { english }
}
enum ChatFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
@MainActor enum ChatKeychain {
    static func read(endpoint: String) throws -> String { "fixture-harness-secret-do-not-persist" }
}
@MainActor final class ChatStore {
    static let shared = ChatStore()
    var endpoint = ""
    var model = "deepseek-flash"
    static func validatedURL(_ endpoint: String) throws -> URL { URL(string: endpoint)! }
}

@main struct AgentTaskTests {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        fatalError("Timed out")
    }
    @MainActor static func main() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let visible = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let above = AgentBubbleGeometry.place(near: CGRect(x: -800, y: 100, width: 120, height: 240), visible: visible, desiredHeight: 228)
        precondition(above.above && above.frame.minY > 340 && visible.contains(above.frame))
        let below = AgentBubbleGeometry.place(near: CGRect(x: -200, y: 650, width: 120, height: 240), visible: visible, desiredHeight: 228)
        precondition(!below.above && below.frame.maxY < 650 && visible.contains(below.frame))
        for pet in [CGRect(x: -1450, y: 400, width: 96, height: 90), CGRect(x: -60, y: 400, width: 96, height: 90)] {
            let placed = AgentBubbleGeometry.place(near: pet, visible: visible, desiredHeight: 432)
            precondition(visible.contains(placed.frame))
            precondition(placed.tailX >= 28 && placed.tailX <= placed.frame.width - 28)
        }
        let smallScreen = CGRect(x: 0, y: 0, width: 320, height: 300)
        let small = AgentBubbleGeometry.place(near: CGRect(x: 50, y: 100, width: 100, height: 100), visible: smallScreen, desiredHeight: 432)
        precondition(smallScreen.contains(small.frame))
        print("PASS: bubble placement above/below, edge clamping, external display coordinates and small screen")
        // Tests use the already installed runtime, but isolated tasks/checkpoints.
        let runtime = temp.appendingPathComponent("AgentRuntime")
        try FileManager.default.createSymbolicLink(at: runtime, withDestinationURL:
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BaifanYu/AgentRuntime"))
        let work = temp.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        ChatStore.shared.endpoint = CommandLine.arguments[1]
        let savedWorkspace = UserDefaults.standard.object(forKey: "agent.workspace")
        defer {
            if let savedWorkspace { UserDefaults.standard.set(savedWorkspace, forKey: "agent.workspace") }
            else { UserDefaults.standard.removeObject(forKey: "agent.workspace") }
        }
        let store = AgentTaskStore(support: temp)
        store.workspace = work.path
        store.checkRuntime()
        try await wait { !store.checking }
        precondition(store.runtimeReady)
        precondition(store.submit("TASK:WRITE"))
        precondition(!store.submit("TASK:READ"), "Must not overlap tasks")
        try await wait { !store.approvals.isEmpty || !store.isBusy }
        precondition(store.approvals.first?.name == "write", store.jobs.first?.result ?? "Missing approval")
        precondition(!FileManager.default.fileExists(atPath: work.appendingPathComponent("write.txt").path))
        store.decide(approve: true)
        try await wait { !store.isBusy }
        precondition(store.jobs.first?.status == "completed", store.jobs.first?.result ?? "No result")
        let written = try String(contentsOf: work.appendingPathComponent("write.txt"), encoding: .utf8)
        precondition(written == "written by harness")
        let restored = AgentTaskStore(support: temp)
        precondition(restored.jobs.first?.status == "completed")
        precondition(restored.jobs.first?.result.contains("DONE") == true)
        precondition(restored.jobs.first?.reply?.contains("DONE") == true)
        precondition(restored.jobs.first?.activity?.isEmpty == false)
        // Existing archives from before the speech-bubble UI have no activity/reply/plan fields.
        let archiveURL = temp.appendingPathComponent("tasks.json")
        var old = try JSONSerialization.jsonObject(with: Data(contentsOf: archiveURL)) as! [[String: Any]]
        for i in old.indices {
            old[i].removeValue(forKey: "reply")
            old[i].removeValue(forKey: "activity")
            old[i].removeValue(forKey: "plan")
            old[i].removeValue(forKey: "engine")
        }
        try JSONSerialization.data(withJSONObject: old).write(to: archiveURL)
        let legacy = AgentTaskStore(support: temp)
        precondition(legacy.jobs.count == restored.jobs.count && legacy.error == nil && legacy.jobs.first?.engine == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: temp.appendingPathComponent("tasks.json").path)[.posixPermissions] as? NSNumber
        precondition(permissions?.intValue == 0o600)
        precondition(store.submit("TASK:REJECT"))
        try await wait { !store.approvals.isEmpty }
        store.decide(approve: false)
        try await wait { !store.isBusy }
        precondition(!FileManager.default.fileExists(atPath: work.appendingPathComponent("reject.txt").path))
        precondition(store.submit("TASK:CANCEL"))
        try await wait { !store.approvals.isEmpty }
        store.stop()
        try await wait { !store.isBusy }
        precondition(store.jobs.first?.status == "cancelled")
        let completed = store.jobs.first!
        store.delete(completed)
        precondition(!store.jobs.contains { $0.id == completed.id })
        print("PASS: Swift process bridge, approvals, rejection, cancellation, single-task execution, history and file permissions")
        let corrupt = temp.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        let file = corrupt.appendingPathComponent("tasks.json")
        try Data("corrupt".utf8).write(to: file)
        let broken = AgentTaskStore(support: corrupt)
        broken.checkRuntime()
        try await wait { !broken.checking }
        precondition(broken.error != nil)
        precondition(!broken.submit("TASK:WRITE"))
        let original = try Data(contentsOf: file)
        precondition(original == Data("corrupt".utf8))
        print("PASS: corrupt task archive is preserved")
    }
}
