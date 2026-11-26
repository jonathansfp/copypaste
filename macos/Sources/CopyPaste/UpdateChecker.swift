import AppKit

/// Once a week, asks GitHub for the latest release; if there is a newer version, offers to download it.
@MainActor
enum UpdateChecker {
    private static let lastKey = "update.lastCheck"
    private static let api = URL(string: "https://api.github.com/repos/jonathansfp/copypaste/releases/latest")!
    static let downloadURL = URL(string: "https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-macOS.dmg")!
    private static var timer: Timer?
    /// The new version's .zip, found by the last check.
    private static var pending: (url: URL, size: Int, version: String)?
    private static var installing = false

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Checks now if a week has passed, then keeps checking every few hours while the app runs.
    static func start() {
        checkIfDue()
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { _ in Task { @MainActor in checkIfDue() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 7 * 24 * 3600 else { return }
        Task { await check(manual: false) }
    }

    static func check(manual: Bool) async {
        var r = URLRequest(url: api)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("CopyPaste-Mac", forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 20
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            Diag.log("atualização: não consegui verificar")
            if manual { alert(L("Não consegui verificar agora"), L("Confira a conexão com a internet e tente de novo."), update: false) }
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastKey)
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        Diag.log("atualização: atual \(current), mais recente \(latest)")
        if isNewer(latest, than: current) {
            let notes = (json["name"] as? String).map { "\n\n\($0)" } ?? ""
            let zip = (json["assets"] as? [[String: Any]])?.first { ($0["name"] as? String) == "CopyPaste-macOS.zip" }
            pending = zip.flatMap { a in
                (a["browser_download_url"] as? String).flatMap(URL.init(string:)).map { (url: $0, size: a["size"] as? Int ?? 0, version: latest) }
            }
            alert(L("Nova versão do CopyPaste: %@", latest),
                  L("Você está na %@. Clique em Atualizar agora: o CopyPaste baixa a nova versão, se substitui e abre de novo sozinho. Seu histórico e as configurações são mantidos.", current) + notes,
                  update: true)
        } else if manual {
            alert(L("Você já tem a versão mais recente"), "CopyPaste \(current).", update: false)
        }
    }

    /// Downloads the new version, swaps the app in place and reopens it. On any problem, falls back to
    /// opening the .dmg download so the person can update by hand.
    private static func install(_ p: (url: URL, size: Int, version: String)) async {
        guard !installing else { return }
        installing = true
        defer { installing = false }
        let dest = URL(fileURLWithPath: Bundle.main.bundlePath)
        let fm = FileManager.default
        do {
            guard fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
                throw AIError(message: L("Sem permissão para trocar o app em %@.", dest.deletingLastPathComponent().path))
            }
            Toast.show(L("Baixando a atualização %@…", p.version), symbol: "arrow.down.circle.fill", duration: 4)
            Diag.log("atualização: baixando \(p.url.absoluteString)")
            var req = URLRequest(url: p.url)
            req.timeoutInterval = 60
            let (file, resp) = try await URLSession.shared.download(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw AIError(message: L("O download falhou.")) }
            let got = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            if p.size > 0, got != p.size { throw AIError(message: L("O download veio incompleto.")) }

            let work = fm.temporaryDirectory.appendingPathComponent("CopyPaste-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", file.path, work.path])
            let fresh = work.appendingPathComponent("CopyPaste.app")
            let info = NSDictionary(contentsOf: fresh.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  info?["CFBundleShortVersionString"] as? String == p.version
            else { throw AIError(message: L("O pacote baixado não é a versão esperada.")) }
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])

            // Once this app quits: keep the old copy aside, move the new one in (or put the old back), reopen.
            let script = [
                "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done",
                "rm -rf \"$3.old\"",
                "mv \"$3\" \"$3.old\" && { mv \"$2\" \"$3\" || mv \"$3.old\" \"$3\"; }",
                "rm -rf \"$3.old\" \"$4\"",
                "open \"$3\"",
            ].joined(separator: "\n")
            let sh = Process()
            sh.executableURL = URL(fileURLWithPath: "/bin/sh")
            sh.arguments = ["-c", script, "sh", "\(ProcessInfo.processInfo.processIdentifier)", fresh.path, dest.path, work.path]
            try sh.run()
            Diag.log("atualização: instalando \(p.version) e reabrindo")
            Toast.show(L("Atualizando para a %@ e reabrindo…", p.version), symbol: "arrow.triangle.2.circlepath", duration: 2)
            try? await Task.sleep(nanoseconds: 800_000_000)
            NSApp.terminate(nil)
        } catch {
            Diag.log("atualização: falhou: \(error.localizedDescription)")
            alert(L("Não consegui atualizar sozinho"),
                  L("%@ Vou abrir o download: abra o arquivo e arraste o CopyPaste para Aplicativos, substituindo o atual.", error.localizedDescription),
                  update: false)
            NSWorkspace.shared.open(downloadURL)
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw AIError(message: L("Falha ao preparar a atualização.")) }
        return p.terminationStatus
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func alert(_ title: String, _ text: String, update: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.icon = NSApp.applicationIconImage
        if update {
            a.addButton(withTitle: pending != nil ? L("Atualizar agora") : L("Baixar atualização"))
            a.addButton(withTitle: L("Ver novidades"))
            a.addButton(withTitle: L("Depois"))
            switch a.runModal() {
            case .alertFirstButtonReturn:
                if let p = pending { Task { await install(p) } } else { NSWorkspace.shared.open(downloadURL) }
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(URL(string: "https://github.com/jonathansfp/copypaste/releases/latest")!)
            default: break
            }
        } else {
            a.addButton(withTitle: "OK")
            a.runModal()
        }
    }
}
