import Foundation
import Darwin

@main struct RuntimeInstallerTests {
    static func main() async {
        do { try await runTests() }
        catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func runTests() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--install" {
            let installer = AgentRuntimeInstaller(base: URL(fileURLWithPath: CommandLine.arguments[2]))
            let layout = try await installer.install { phase in print(phase.english) }
            precondition(layout.ready)
            print("READY: " + layout.directory.path)
            return
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let data = temp.appendingPathComponent("sample")
        try Data("abc".utf8).write(to: data)
        let digest = try AgentRuntimeInstaller.hash(data)
        precondition(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try AgentRuntimeInstaller.validateMembers("python/bin/python3\npython/lib/site.py\n")
        for bad in ["../outside", "/absolute", "python/../../escape", "python\\..\\escape"] {
            do { try AgentRuntimeInstaller.validateMembers(bad); fatalError("Accepted unsafe archive") }
            catch {}
        }
        for arch in ["arm64", "x64"] {
            let assets = try AgentRuntimeInstaller.assets(architecture: arch)
            precondition(assets.python.sha256.count == 64 && assets.harness.sha256.count == 64)
            precondition(assets.python.urls.allSatisfy(RuntimeDownloadPolicy.allows))
            precondition(assets.harness.urls.allSatisfy(RuntimeDownloadPolicy.allows))
        }
        precondition(!RuntimeDownloadPolicy.allows(URL(string: "http://files.pythonhosted.org/payload")!))
        precondition(!RuntimeDownloadPolicy.allows(URL(string: "https://evil.test/payload")!))
        precondition(!RuntimeDownloadPolicy.allows(URL(string: "https://github.com.evil.test/payload")!))
        precondition(!RuntimeDownloadPolicy.allows(URL(string: "https://user:password@github.com/payload")!))
        let layout = ManagedAgentRuntime(base: temp, architecture: "arm64")
        precondition(!layout.ready)
        try FileManager.default.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        try ManagedAgentRuntime.release.write(to: layout.directory.appendingPathComponent("complete"), atomically: true, encoding: .utf8)
        precondition(!layout.ready, "A marker alone must never make an incomplete install usable")
        let lockedBase = temp.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: lockedBase, withIntermediateDirectories: true)
        let lock = open(lockedBase.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR, 0o600)
        precondition(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0)
        do {
            _ = try await AgentRuntimeInstaller(base: lockedBase).install { _ in }
            fatalError("Concurrent installer was admitted")
        } catch { precondition(error.localizedDescription.contains("Another")) }
        flock(lock, LOCK_UN); close(lock)
        let cancelledBase = temp.appendingPathComponent("cancelled")
        let cancelled = Task { try await AgentRuntimeInstaller(base: cancelledBase).install { _ in } }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled installation succeeded") }
        catch { precondition(error is CancellationError) }
        precondition(!ManagedAgentRuntime(base: cancelledBase, architecture: ManagedAgentRuntime.hostArchitecture).ready)
        print("PASS: SHA-256, archive boundaries, redirect policy, architecture pins, incomplete installs, concurrent-install lock and cancellation")
    }
}
