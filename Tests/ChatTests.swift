// Standalone harness: no Xcode / XCTest dependency.
import Foundation

enum TestLanguage { case simplifiedChinese, traditionalChinese, english }
@MainActor final class LocalizationManager {
    static let shared = LocalizationManager()
    var resolved: TestLanguage = .english
}

@main struct ChatTests {
    @MainActor static func main() async throws {
        func check(_ condition: Bool, _ message: String) {
            if !condition { fatalError(message) }
        }
        for address in ["https://example.com/v1/chat/completions", "http://localhost:11434/v1/chat/completions"] {
            _ = try ChatStore.validatedURL(address)
        }
        for address in ["http://example.com/chat", "https://key@example.com/chat", "file:///tmp/chat", "not a URL", "https://example.com/chat?key=secret"] {
            do { _ = try ChatStore.validatedURL(address); fatalError("Accepted invalid endpoint") }
            catch {}
        }
        let chunk = try JSONDecoder().decode(ChatStreamEvent.self, from: Data(#"{"choices":[{"delta":{"content":"白饭鱼 🐟"}}]}"#.utf8))
        check(chunk.choices?.first?.delta?.content == "白饭鱼 🐟", "Unicode chunk")
        let reasoning = try JSONDecoder().decode(ChatStreamEvent.self, from: Data(#"{"choices":[{"delta":{"reasoning_content":"hidden"}}]}"#.utf8))
        check(reasoning.choices?.first?.delta?.content == nil, "Reasoning is not reply text")
        let suite = "BaifanYuTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let history = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("chat.json")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: history.deletingLastPathComponent())
        }
        let root = CommandLine.arguments[1]
        defaults.set(root + "/success", forKey: "chat.endpoint")
        defaults.set("mock-model", forKey: "chat.model")
        let store = ChatStore(defaults: defaults, historyURL: history)
        store.send("你好")
        while store.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(store.error == nil, "Streaming error: " + (store.error ?? ""))
        check(store.messages.last?.content == "你好，白饭鱼 🐟", "Stream chunks not assembled")
        let restored = ChatStore(defaults: defaults, historyURL: history)
        check(restored.messages.map(\.id) == store.messages.map(\.id), "History did not persist")
        let originalID = restored.activeID
        restored.newConversation()
        check(restored.activeID != originalID && restored.messages.isEmpty, "New conversation inherited messages")
        let secondID = restored.activeID
        restored.send("NEW_SESSION")
        while restored.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(restored.error == nil, "New session send failed")
        restored.selectConversation(originalID)
        check(restored.messages.first?.content == "你好", "Switch lost original messages")
        restored.deleteConversation(secondID)
        let afterDelete = ChatStore(defaults: defaults, historyURL: history)
        check(afterDelete.conversations.count == 1 && afterDelete.activeID == originalID, "Delete not persisted")
        restored.clear()
        check(restored.messages.isEmpty, "Clear failed")
        let cleared = ChatStore(defaults: defaults, historyURL: history)
        check(cleared.messages.isEmpty, "Clear did not persist")
        defaults.set(root + "/unauthorized", forKey: "chat.endpoint")
        let denied = ChatStore(defaults: defaults, historyURL: history)
        denied.send("test")
        while denied.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(denied.error?.contains("401") == true, "HTTP error not surfaced")
        check(denied.messages.count == 1, "Empty failed reply persisted")
        defaults.set(root + "/slow", forKey: "chat.endpoint")
        let slow = ChatStore(defaults: defaults, historyURL: history)
        slow.send("stop test")
        try await Task.sleep(for: .milliseconds(200))
        slow.stop()
        while slow.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(slow.error == nil, "Cancellation treated as error")
        defaults.set(root + "/redirect", forKey: "chat.endpoint")
        let redirect = ChatStore(defaults: defaults, historyURL: history)
        redirect.send("redirect test")
        while redirect.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(redirect.error?.contains("302") == true, "Redirect was not blocked")
        let legacyURL = history.deletingLastPathComponent().appendingPathComponent("legacy.json")
        let legacy = [ChatMessage(role: "user", content: "legacy conversation")]
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        let migrated = ChatStore(defaults: defaults, historyURL: legacyURL)
        check(migrated.messages.first?.id == legacy.first?.id, "Migration lost legacy IDs")
        migrated.newConversation()
        let migratedAgain = ChatStore(defaults: defaults, historyURL: legacyURL)
        check(migratedAgain.conversations.count == 2, "Migration was not persisted")
        migratedAgain.deleteConversation(migratedAgain.activeID)
        migratedAgain.deleteConversation(migratedAgain.activeID)
        check(migratedAgain.conversations.count == 1 && migratedAgain.messages.isEmpty, "Delete last session failed")
        let corruptedURL = history.deletingLastPathComponent().appendingPathComponent("corrupt.json")
        let corrupted = Data("broken JSON".utf8)
        try corrupted.write(to: corruptedURL)
        let invalid = ChatStore(defaults: defaults, historyURL: corruptedURL)
        invalid.newConversation()
        invalid.clear()
        invalid.send("do not overwrite")
        check(try Data(contentsOf: corruptedURL) == corrupted, "Corrupt history was overwritten")
        let longHistory = (0..<30).map { ChatMessage(role: $0 % 2 == 0 ? "user" : "assistant", content: String(repeating: "鱼", count: 1500)) }
            + [ChatMessage(role: "user", content: "latest")]
        let context = ChatContext.messages(from: longHistory)
        check(context.count <= 21 && context.reduce(0, { $0 + $1.content.count }) <= 12_000, "Context budget exceeded")
        check(context.first?.role == "user" && context.last?.content == "latest", "Context broke latest turn")
        check(longHistory.count == 31, "Context trimming modified history")
        restored.send(String(repeating: "鱼", count: 8001))
        check(!restored.isSending && restored.messages.isEmpty, "Oversized input was accepted")
        // Seed a long, realistic-sized transcript without touching the user's data.
        let seededMessages = (0..<20).map { i in
            ChatMessage(role: i % 2 == 0 ? "user" : "assistant",
                        content: (i == 0 ? "OLD_ONLY" : "") + String(repeating: "鱼", count: 300))
        }
        func seed(_ name: String, endpoint: String) throws -> (ChatStore, URL) {
            let target = history.deletingLastPathComponent().appendingPathComponent(name + ".json")
            let conversation = ChatConversation(messages: seededMessages)
            try JSONEncoder().encode(ChatArchive(activeID: conversation.id, conversations: [conversation])).write(to: target)
            defaults.set(root + endpoint, forKey: "chat.endpoint")
            return (ChatStore(defaults: defaults, historyURL: target), target)
        }
        let (compacted, compactedURL) = try seed("compacted", endpoint: "/summary-ok")
        compacted.send("continue")
        while compacted.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(compacted.error == nil, "Compaction send failed: " + (compacted.error ?? ""))
        let memory = compacted.conversations.first?.summary
        check(memory?.text.contains("MEMORY_OK") == true, "Summary was not committed")
        check(compacted.messages.count == 22, "Compaction deleted raw transcript")
        check(compacted.lastUsage?.total_tokens == 120 && compacted.lastSummaryUsage?.total_tokens == 120, "Usage not decoded independently")
        let resume = ChatStore(defaults: defaults, historyURL: compactedURL)
        check(resume.conversations.first?.summary?.throughMessageID == memory?.throughMessageID, "Summary coverage did not persist")
        resume.send("another short question")
        while resume.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(resume.error == nil && resume.lastSummaryUsage == nil, "Repeated compaction unexpectedly")
        check(resume.lastEstimatedInputTokens < ChatContext.estimatedTokens(seededMessages), "Input not reduced")
        resume.newConversation()
        check(resume.conversations.first(where: { $0.id == resume.activeID })?.summary == nil, "New session inherited summary")
        resume.selectConversation(compacted.activeID)
        resume.clear()
        check(resume.conversations.first(where: { $0.id == resume.activeID })?.summary == nil, "Clear kept old memory")
        let (failedSummary, _) = try seed("summaryFailure", endpoint: "/summary-fail")
        failedSummary.send("continue after summary failure")
        while failedSummary.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(failedSummary.messages.last?.role == "assistant", "Summary failure prevented normal reply")
        check(failedSummary.conversations.first?.summary == nil && failedSummary.contextNotice != nil, "Failure committed invalid summary")
        failedSummary.send("retry chat without another summary request")
        while failedSummary.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(failedSummary.error == nil, "Fallback retry failed")
        let (cancelSummary, _) = try seed("summaryCancel", endpoint: "/summary-cancel")
        cancelSummary.send("cancel before summary finishes")
        while !cancelSummary.isCompacting && cancelSummary.isSending { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        cancelSummary.stop()
        while cancelSummary.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(cancelSummary.conversations.first?.summary == nil && cancelSummary.messages.count == 21, "Cancelled summary modified memory or replied")
        check(cancelSummary.error == nil, "Cancelled summary reported as failure")
        let staleSummary = ChatSummary(text: "stale", throughMessageID: UUID())
        check(ChatContext.unsummarized(seededMessages, summary: staleSummary).count == seededMessages.count, "Stale coverage dropped history")
        defaults.set(root + "/success", forKey: "chat.endpoint")
        let usageDisabled = ChatStore(defaults: defaults, historyURL: history)
        usageDisabled.requestUsage = false
        usageDisabled.send("no usage")
        while usageDisabled.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(usageDisabled.error == nil && usageDisabled.lastUsage == nil, "Provider without usage unsupported")
        defaults.set(true, forKey: "chat.requestUsage")
        let manyShort = (0..<40).map { i in ChatMessage(role: i % 2 == 0 ? "user" : "assistant", content: "hello") }
            + [ChatMessage(role: "user", content: "latest")]
        check(ChatContext.requestMessages(history: manyShort, summary: nil, system: "pet").count == 42, "Short exchanges were discarded prematurely")
        var rollingHistory = seededMessages
        rollingHistory += (0..<20).map { i in ChatMessage(role: i % 2 == 0 ? "user" : "assistant", content: String(repeating: "新", count: 300)) }
        let rollingSummary = ChatSummary(text: "MEMORY_OK: established facts", throughMessageID: seededMessages.last!.id)
        let rollingConversation = ChatConversation(messages: rollingHistory, summary: rollingSummary)
        let rollingURL = history.deletingLastPathComponent().appendingPathComponent("rolling.json")
        try JSONEncoder().encode(ChatArchive(activeID: rollingConversation.id, conversations: [rollingConversation])).write(to: rollingURL)
        defaults.set(root + "/summary-roll", forKey: "chat.endpoint")
        let rolling = ChatStore(defaults: defaults, historyURL: rollingURL)
        rolling.send("continue rolling")
        while rolling.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(rolling.error == nil && rolling.conversations.first?.summary?.throughMessageID != rollingSummary.throughMessageID, "Rolling summary did not advance coverage")
        let preservedURL = history.deletingLastPathComponent().appendingPathComponent("preserved.json")
        try JSONEncoder().encode(ChatArchive(activeID: rollingConversation.id, conversations: [rollingConversation])).write(to: preservedURL)
        defaults.set(root + "/summary-oldfail", forKey: "chat.endpoint")
        let preserved = ChatStore(defaults: defaults, historyURL: preservedURL)
        preserved.send("keep memory on failure")
        while preserved.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(preserved.conversations.first?.summary?.throughMessageID == rollingSummary.throughMessageID, "Failed summary replaced old coverage")
        let reloadedPreserved = ChatStore(defaults: defaults, historyURL: preservedURL)
        check(reloadedPreserved.conversations.first?.summary?.text == rollingSummary.text, "Failure lost persisted memory")
        let (truncated, _) = try seed("truncated", endpoint: "/summary-truncated")
        truncated.send("incomplete summary")
        while truncated.isSending { try await Task.sleep(for: .milliseconds(20)) }
        check(truncated.conversations.first?.summary == nil && truncated.messages.last?.role == "assistant", "Truncated summary was committed or prevented chat")
        print("PASS: short-turn retention, incremental summary coverage, saved memory on failure, truncated-summary rejection")
        print("PASS: compaction, summary reuse, transcript preservation, independent usage, failure cooldown, cancellation, stale memory, session isolation")
        print("PASS: sessions, isolation, deletion, migration, corrupt-file protection, context budget, input limit")
        print("PASS: endpoint validation, Unicode stream, reasoning exclusion, persistence, clear, HTTP errors, cancellation, redirect refusal")
    }
}
