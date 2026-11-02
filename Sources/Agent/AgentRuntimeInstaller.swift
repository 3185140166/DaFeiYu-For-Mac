import Foundation
import CryptoKit
import Darwin

struct ManagedAgentRuntime: Sendable {
    static let release = "dsh-0.2.1rc2-python-3.12.16-v1"
    let base: URL
    let architecture: String
    var directory: URL { base.appendingPathComponent("managed/\(Self.release)-\(architecture)") }
    var python: URL { directory.appendingPathComponent("python/bin/python3") }
    var harness: URL { directory.appendingPathComponent("harness/deepseek_harness_runtime/runtime/deepseek-harness-sdk-runtime-macos-\(architecture)") }
    var ready: Bool {
        let marker = try? String(contentsOf: directory.appendingPathComponent("complete"), encoding: .utf8)
        return marker == Self.release && FileManager.default.isExecutableFile(atPath: python.path)
            && FileManager.default.isExecutableFile(atPath: harness.path)
            && FileManager.default.isExecutableFile(atPath: harness.path + "-rg")
            && FileManager.default.isExecutableFile(atPath: harness.path + "-spawn-helper")
    }
    static var hostArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }
}

enum AgentRuntimePhase: Sendable {
    case cache, python, harness, verify, unpack, test
    var chinese: String {
        switch self {
        case .cache: return "检查已下载的后台…"
        case .python: return "下载工作环境（1/2）…"
        case .harness: return "下载 Harness 后台（2/2）…"
        case .verify: return "校验下载完整性…"
        case .unpack: return "展开工作环境…"
        case .test: return "验证后台能否启动…"
        }
    }
    var english: String {
        switch self {
        case .cache: return "Checking cached downloads…"
        case .python: return "Downloading task environment (1/2)…"
        case .harness: return "Downloading Harness (2/2)…"
        case .verify: return "Verifying downloads…"
        case .unpack: return "Preparing task environment…"
        case .test: return "Checking runtime startup…"
        }
    }
}

struct AgentRuntimeInstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs inside the native app: bootstrapping never depends on system Python, Node, npm or pip.
actor AgentRuntimeInstaller {
    struct Asset: Sendable {
        let urls: [URL]
        let sha256: String
        let fileName: String
    }
    let layout: ManagedAgentRuntime
    init(base: URL, architecture: String = ManagedAgentRuntime.hostArchitecture) {
        layout = ManagedAgentRuntime(base: base, architecture: architecture)
    }

    static func assets(architecture: String) throws -> (python: Asset, harness: Asset) {
        guard ["arm64", "x64"].contains(architecture) else { throw AgentRuntimeInstallError(message: "Unsupported Mac architecture") }
        let arm = architecture == "arm64"
        let pythonName = "cpython-3.12.16+20261026-\(arm ? "aarch64" : "x86_64")-apple-darwin-install_only_stripped.tar.gz"
        let python = Asset(urls: [URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20261026/\(pythonName)")!],
            sha256: arm ? "353d5f1b4fd2715e7053f12f068435d5bbad16b91e057006b5d01e0925709a7e" : "37c38fda76fec1fbf310adcbafb7f0d96af13b5511bf8ea954c3aa8eec185734", fileName: pythonName)
        let wheel = "deepseek_harness_runtime_bin-0.2.1rc2-py3-none-macosx_14_0_\(arm ? "arm64" : "x86_64").whl"
        let path = arm ? "10/99/723905c63929056e05494e8a659bc8eb9adf671ee6712fb4316930b97ac8" : "7b/b5/8bd76d1247955ba1f502bd684f9307352a879d703475b547cb6934495b6e"
        let harness = Asset(urls: [URL(string: "https://pypi.tuna.tsinghua.edu.cn/packages/\(path)/\(wheel)")!,
                                   URL(string: "https://files.pythonhosted.org/packages/\(path)/\(wheel)")!],
            sha256: arm ? "96a173abd14141d5328a78791b69729cbfe22fa3e9daf1dc2600d0daa4d6bb28" : "80614eee24916ce97d692baf8aed3ba146ed00fc2155d266cb0ede98d9354139", fileName: wheel)
        return (python, harness)
    }

    func install(progress: @escaping @Sendable (AgentRuntimePhase) -> Void) async throws -> ManagedAgentRuntime {
        let files = FileManager.default
        try files.createDirectory(at: layout.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = open(layout.base.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw AgentRuntimeInstallError(message: "Cannot create installer lock") }
        defer { flock(lock, LOCK_UN); close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw AgentRuntimeInstallError(message: "Another DaFeiYu instance is preparing the runtime. Try again shortly.") }
        // A process quit can bypass defer; these app-owned staging folders were never activated.
        for entry in try files.contentsOfDirectory(at: layout.base, includingPropertiesForKeys: nil)
            where entry.lastPathComponent.hasPrefix(".prepare-") { try? files.removeItem(at: entry) }
        if layout.ready {
            progress(.test)
            let current = layout
            if (try? await Task.detached(operation: { try Self.validateStartup(current); return true }).value) == true { return layout }
            try Task.checkCancellation()
        }
        progress(.cache)
        let assets = try Self.assets(architecture: layout.architecture)
        let python = try await download(assets.python, phase: .python, progress: progress)
        let harness = try await download(assets.harness, phase: .harness, progress: progress)
        try Task.checkCancellation()
        let stage = layout.base.appendingPathComponent(".prepare-\(UUID().uuidString)")
        try files.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: stage) }
        progress(.unpack)
        let architecture = layout.architecture
        try await Task.detached {
            let files = FileManager.default
            try Self.extract(python, to: stage, zip: false)
            let target = stage.appendingPathComponent("harness")
            try files.createDirectory(at: target, withIntermediateDirectories: true)
            try Self.extract(harness, to: target, zip: true)
            let binary = target.appendingPathComponent("deepseek_harness_runtime/runtime/deepseek-harness-sdk-runtime-macos-\(architecture)")
            for path in [stage.appendingPathComponent("python/bin/python3").path, binary.path, binary.path + "-rg", binary.path + "-spawn-helper"] {
                guard files.fileExists(atPath: path) else { throw AgentRuntimeInstallError(message: "Runtime package is missing required files") }
                // ZIP readers do not consistently restore Unix executable mode.
                try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }.value
        try Task.checkCancellation()
        // Publish only a complete version. A broken prior copy is kept until the new copy is ready.
        let parent = layout.directory.deletingLastPathComponent()
        try files.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let backup = parent.appendingPathComponent(".previous-\(UUID().uuidString)")
        let hadPrevious = files.fileExists(atPath: layout.directory.path)
        if hadPrevious { try files.moveItem(at: layout.directory, to: backup) }
        do { try files.moveItem(at: stage, to: layout.directory) }
        catch {
            if hadPrevious { try? files.moveItem(at: backup, to: layout.directory) }
            throw error
        }
        do {
            progress(.test)
            let target = layout
            // Test after relocation: a supposedly portable environment must work at its final path.
            try await Task.detached {
                try Self.validateStartup(target)
            }.value
            try Task.checkCancellation()
            try ManagedAgentRuntime.release.write(to: layout.directory.appendingPathComponent("complete"), atomically: true, encoding: .utf8)
            try? files.removeItem(at: layout.directory.appendingPathComponent(".smoke-home"))
            if hadPrevious { try? files.removeItem(at: backup) }
            return layout
        } catch {
            try? files.removeItem(at: layout.directory)
            if hadPrevious { try? files.moveItem(at: backup, to: layout.directory) }
            throw error
        }
    }

    private func download(_ asset: Asset, phase: AgentRuntimePhase,
                          progress: @escaping @Sendable (AgentRuntimePhase) -> Void) async throws -> URL {
        let files = FileManager.default
        let cache = layout.base.appendingPathComponent("downloads")
        try files.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = cache.appendingPathComponent(asset.sha256 + "-" + asset.fileName)
        if files.fileExists(atPath: destination.path) {
            if try await Task.detached(operation: { try Self.hash(destination) == asset.sha256 }).value { return destination }
            try files.removeItem(at: destination)
        }
        var lastError: Error = AgentRuntimeInstallError(message: "Download failed")
        for source in asset.urls {
            try Task.checkCancellation()
            guard RuntimeDownloadPolicy.allows(source) else { throw AgentRuntimeInstallError(message: "Untrusted runtime download source") }
            progress(phase)
            let session = URLSession(configuration: {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 45
                config.timeoutIntervalForResource = 900
                return config
            }(), delegate: RuntimeDownloadPolicy(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            do {
                let (temporary, response) = try await session.download(from: source)
                defer { try? files.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw AgentRuntimeInstallError(message: "Download server returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
                progress(.verify)
                guard try await Task.detached(operation: { try Self.hash(temporary) == asset.sha256 }).value else {
                    throw AgentRuntimeInstallError(message: "Download integrity check failed. Retry to download a clean copy.")
                }
                try Task.checkCancellation()
                try files.moveItem(at: temporary, to: destination)
                return destination
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }

    nonisolated static func validateStartup(_ target: ManagedAgentRuntime) throws {
        defer { try? FileManager.default.removeItem(at: target.directory.appendingPathComponent(".smoke-home")) }
        try run(target.python, ["-I", "-c", "import ssl, http.server, selectors; print('ready')"])
        try run(target.harness, ["--profile", "sdk", "--help"], environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "DSH_HOME": target.directory.appendingPathComponent(".smoke-home").path])
    }

    nonisolated static func hash(_ file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var digest = SHA256()
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func validateMembers(_ listing: String) throws {
        for entry in listing.split(separator: "\n") {
            let path = String(entry)
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\\") else {
                throw AgentRuntimeInstallError(message: "Unsafe path in runtime archive")
            }
        }
    }

    nonisolated static func extract(_ archive: URL, to target: URL, zip: Bool) throws {
        let list = try run(URL(fileURLWithPath: zip ? "/usr/bin/unzip" : "/usr/bin/tar"), zip ? ["-Z1", archive.path] : ["-tzf", archive.path])
        try validateMembers(list)
        if zip { try run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, target.path]) }
        else { try run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", target.path]) }
    }

    @discardableResult nonisolated static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment ?? ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "PYTHONNOUSERSITE": "1"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Bound startup/unpacking even if a downloaded executable fails to exit.
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + 90)
        timer.setEventHandler { if process.isRunning { process.terminate() } }
        timer.resume()
        defer { timer.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AgentRuntimeInstallError(message: "Runtime preparation failed (exit \(process.terminationStatus))") }
        return String(decoding: data, as: UTF8.self)
    }
}

final class RuntimeDownloadPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func allows(_ url: URL) -> Bool {
        url.scheme == "https" && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "files.pythonhosted.org", "pypi.tuna.tsinghua.edu.cn"].contains(url.host ?? "")
            && url.user == nil && url.password == nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allows) == true ? request : nil)
    }
}
