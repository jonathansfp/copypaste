import AppKit
import CryptoKit
import Darwin

/// Built-in AI that runs on the Mac: Google's Gemma 4 E2B (text and audio) on llama.cpp.
///
/// Nothing is bundled in the app: on the user's request it downloads the official llama.cpp runtime
/// and the model, pinned to fixed versions and checked against their SHA-256. While in use, a local
/// server (`llama-server`, OpenAI-compatible) listens only on 127.0.0.1 and is shut down after
/// 10 minutes without use, giving the memory back.
@MainActor
final class LocalAI: ObservableObject {
    static let shared = LocalAI()

    enum State: Equatable {
        case notInstalled
        case downloading(Double, String)
        case installed
        case failed(String)
    }

    @Published private(set) var state: State = .notInstalled
    @Published private(set) var running = false

    struct Asset: Sendable {
        let url: URL
        let sha256: String
        let size: Int64
        let file: String
        let label: String
    }

    nonisolated static let runtimeTag = "b12751"
    nonisolated static let modelName = "Gemma 4 E2B"

    nonisolated private static let hfBase = "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/0314792d7f1f7e229411f620751375812bb9faf2/"

    nonisolated static var runtimeAsset: Asset {
        #if arch(arm64)
        return Asset(url: URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b12751/llama-b12751-bin-macos-arm64.tar.gz")!,
                     sha256: "d6b2790ee9a8f528016976d8f23c0fcbd6310dd739538d0c00088805ef52a490",
                     size: 16_840_406, file: "llama-runtime.tar.gz", label: "motor llama.cpp")
        #else
        return Asset(url: URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b12751/llama-b12751-bin-macos-x64.tar.gz")!,
                     sha256: "80985ebbe0ac3029afb45b9442d1c9aa3cd8ac08b3b22b15f234e5360772377b",
                     size: 12_568_191, file: "llama-runtime.tar.gz", label: "motor llama.cpp")
        #endif
    }

    nonisolated static let modelAsset = Asset(url: URL(string: hfBase + "gemma-4-E2B-it-Q4_K_M.gguf")!,
                                  sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8",
                                  size: 3_106_738_272, file: "gemma-4-E2B-it-Q4_K_M.gguf", label: "modelo Gemma 4")
    nonisolated static let audioAsset = Asset(url: URL(string: hfBase + "mmproj-F16.gguf")!,
                                  sha256: "140be8d7849741f88c50757d529b84373ee8e27052cc2236855b537f4a8215fa",
                                  size: 985_654_080, file: "mmproj-F16.gguf", label: "módulo de voz e imagem")

    nonisolated static var totalBytes: Int64 { runtimeAsset.size + modelAsset.size + audioAsset.size }

    nonisolated static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CopyPaste/IA local", isDirectory: true)
    }()
    var dir: URL { Self.folder }
    private var runtimeDir: URL { Self.runtimeFolder }
    nonisolated private static var runtimeFolder: URL { folder.appendingPathComponent("llama-\(runtimeTag)", isDirectory: true) }

    private var process: Process?
    private var port: Int = 0
    private var lastUse = Date()
    private var idleTimer: Timer?
    private var starting: Task<URL, Error>?
    private var downloadTask: Task<Void, Never>?

    private init() {
        state = isInstalled ? .installed : .notInstalled
    }

    // MARK: Install

    var isInstalled: Bool { Self.installedOnDisk }

    /// Engine and model are on disk (usable from any thread).
    nonisolated static var installedOnDisk: Bool {
        findServer() != nil && hasFile(modelAsset) && hasFile(audioAsset)
    }

    nonisolated private static func hasFile(_ a: Asset) -> Bool {
        let path = folder.appendingPathComponent(a.file).path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
        return size == a.size
    }
    private func hasFile(_ a: Asset) -> Bool { Self.hasFile(a) }

    nonisolated private static func findServer() -> URL? {
        guard let e = FileManager.default.enumerator(at: runtimeFolder, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "llama-server" {
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
    private var serverBinary: URL? { Self.findServer() }

    /// Model already downloaded (only the small engine is missing).
    var hasModelFiles: Bool { hasFile(Self.modelAsset) && hasFile(Self.audioAsset) }

    var diskUsage: Int64 {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func install() {
        guard downloadTask == nil else { return }
        state = .downloading(0, "Preparando…")
        Diag.log("IA local: instalação iniciada")
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let assets = [Self.runtimeAsset, Self.modelAsset, Self.audioAsset]
                var done: Int64 = 0
                for a in assets {
                    let dest = dir.appendingPathComponent(a.file)
                    if a.file != Self.runtimeAsset.file, hasFile(a) {
                        done += a.size
                        continue
                    }
                    let base = done
                    try await Downloader.fetch(a, to: dest) { got in
                        Task { @MainActor in
                            let p = Double(base + got) / Double(Self.totalBytes)
                            self.state = .downloading(p, "Baixando \(a.label)…")
                        }
                    }
                    state = .downloading(Double(base + a.size) / Double(Self.totalBytes), "Conferindo \(a.label)…")
                    let ok = await Task.detached { Self.sha256(of: dest) == a.sha256 }.value
                    guard ok else {
                        try? FileManager.default.removeItem(at: dest)
                        throw AIError(message: "O arquivo \(a.label) chegou corrompido. Tente de novo.")
                    }
                    done += a.size
                }
                // Unpacks the engine.
                try? FileManager.default.removeItem(at: runtimeDir)
                try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
                let tar = Process()
                tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tar.arguments = ["-xzf", dir.appendingPathComponent(Self.runtimeAsset.file).path, "-C", runtimeDir.path]
                try tar.run()
                tar.waitUntilExit()
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.runtimeAsset.file))
                guard tar.terminationStatus == 0, serverBinary != nil else {
                    throw AIError(message: "Não consegui instalar o motor da IA local.")
                }
                state = .installed
                Diag.log("IA local instalada")
                if DictationSettings.shared.polishProvider == nil { DictationSettings.shared.polishProvider = .local }
                DictationSettings.shared.objectWillChange.send()
            } catch is CancellationError {
                state = isInstalled ? .installed : .notInstalled
            } catch {
                Diag.log("IA local: falha ao baixar: \(error)")
                state = .failed(error.localizedDescription)
            }
            downloadTask = nil
        }
    }

    func cancelInstall() {
        downloadTask?.cancel()
        Downloader.cancelAll()
    }

    func remove() {
        stop()
        try? FileManager.default.removeItem(at: dir)
        state = .notInstalled
        let s = DictationSettings.shared
        if s.polishProvider == .local { s.polishProvider = s.connected.filter { $0 != .local }.sorted { $0.rawValue < $1.rawValue }.first }
        if s.engine == .local { s.engine = .apple }
        s.objectWillChange.send()
    }

    nonisolated static func sha256(of url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Self-test

    @Published private(set) var testResult: String?
    @Published private(set) var testing = false

    /// Loads the model, cleans up a sample dictation (and transcribes `wav`, if given), timing each step.
    @discardableResult
    func selfTest(wav: URL? = nil) async -> String {
        testing = true
        testResult = nil
        defer { testing = false }
        var lines: [String] = []
        do {
            var t = Date()
            _ = try await ensureRunning()
            lines.append(String(format: "Modelo carregado em %.1f s", Date().timeIntervalSince(t)))
            if let wav {
                t = Date()
                let text = try await AIClient.transcribe(.local, key: "local", model: Self.modelName, wav: wav, language: "pt", hint: "")
                lines.append(String(format: "Transcrição em %.1f s: \"%@\"", Date().timeIntervalSince(t), text))
            }
            t = Date()
            let sample = "é então tipo amanhã a gente se fala às três não quer dizer às quatro e aí vírgula leva o relatório né"
            let out = try await AIClient.complete(.local, key: "local", model: Self.modelName,
                                                  system: DictationPrompts.cleanup(style: .natural, app: nil, terms: []),
                                                  user: "<transcricao>\n\(sample)\n</transcricao>")
            lines.append(String(format: "Ajuste do texto em %.1f s: \"%@\"", Date().timeIntervalSince(t), DictationPrompts.stripWrappers(out)))
        } catch {
            lines.append("Falhou: \(error.localizedDescription)")
        }
        let report = lines.joined(separator: "\n")
        Diag.log("IA local, teste:\n\(report)")
        testResult = report
        return report
    }

    // MARK: Server

    /// Starts the model in the background (e.g. while the user is still talking).
    func prewarm() {
        guard isInstalled else { return }
        Task { _ = try? await ensureRunning() }
    }

    /// Base URL of the OpenAI-compatible API, starting the server if needed.
    func ensureRunning() async throws -> URL {
        guard isInstalled, let bin = serverBinary else {
            throw AIError(message: "Baixe a IA local em Configurações › Ditado por voz.")
        }
        lastUse = Date()
        if let p = process, p.isRunning, running { return baseURL }
        if let s = starting { return try await s.value }
        let task = Task<URL, Error> { @MainActor in
            defer { starting = nil }
            try launch(bin)
            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline {
                guard let p = process, p.isRunning else {
                    throw AIError(message: "A IA local não conseguiu iniciar. \(logTail())")
                }
                if await healthy() {
                    running = true
                    scheduleIdle()
                    return baseURL
                }
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            stop()
            throw AIError(message: "A IA local demorou demais para carregar.")
        }
        starting = task
        return try await task.value
    }

    private var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/v1")! }

    private func launch(_ bin: URL) throws {
        stop()
        port = Self.freePort()
        let p = Process()
        p.executableURL = bin
        p.currentDirectoryURL = bin.deletingLastPathComponent()
        p.arguments = [
            "-m", dir.appendingPathComponent(Self.modelAsset.file).path,
            "--mmproj", dir.appendingPathComponent(Self.audioAsset.file).path,
            "--host", "127.0.0.1", "--port", "\(port)",
            "-c", "8192", "-np", "1",
            "--no-webui", "--reasoning", "off",
        ]
        let log = dir.appendingPathComponent("servidor.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: log) {
            p.standardOutput = h
            p.standardError = h
        }
        p.terminationHandler = { _ in
            Task { @MainActor in LocalAI.shared.running = false }
        }
        try p.run()
        process = p
        Diag.log("IA local: servidor iniciado na porta \(port)")
    }

    private func healthy() async -> Bool {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        r.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private func logTail() -> String {
        let log = dir.appendingPathComponent("servidor.log")
        guard let s = try? String(contentsOf: log, encoding: .utf8) else { return "" }
        let lines = s.split(separator: "\n").suffix(3).joined(separator: " ")
        return String(lines.suffix(240))
    }

    private func scheduleIdle() {
        idleTimer?.invalidate()
        let t = Timer(timeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                let ai = LocalAI.shared
                if Date().timeIntervalSince(ai.lastUse) > 600 { ai.stop() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    func touch() { lastUse = Date() }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        running = false
    }

    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 18_765 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0
            }
        }
        return ok ? Int(UInt16(bigEndian: addr.sin_port)) : 18_765
    }
}

/// Large downloads with progress, written straight to disk.
private enum Downloader {
    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let dest: URL
        let progress: (Int64) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        init(dest: URL, progress: @escaping (Int64) -> Void) {
            self.dest = dest
            self.progress = progress
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64) {
            progress(totalBytesWritten)
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                finish(AIError(message: "O download falhou (erro \(code)). Tente de novo mais tarde."))
                return
            }
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: location, to: dest)
                finish(nil)
            } catch {
                finish(error)
            }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                let cancelled = (error as? URLError)?.code == .cancelled
                finish(cancelled ? CancellationError() : AIError(message: "O download parou: \(error.localizedDescription)"))
            }
        }
        private func finish(_ error: Error?) {
            guard let c = continuation else { return }
            continuation = nil
            if let error { c.resume(throwing: error) } else { c.resume() }
        }
    }

    nonisolated(unsafe) private static var sessions: [URLSession] = []

    static func fetch(_ a: LocalAI.Asset, to dest: URL, progress: @escaping (Int64) -> Void) async throws {
        let delegate = Delegate(dest: dest, progress: progress)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 6
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        sessions.append(session)
        defer {
            session.finishTasksAndInvalidate()
            sessions.removeAll { $0 === session }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                delegate.continuation = c
                session.downloadTask(with: a.url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    static func cancelAll() {
        sessions.forEach { $0.invalidateAndCancel() }
    }
}
