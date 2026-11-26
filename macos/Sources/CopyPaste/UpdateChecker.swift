import AppKit

/// Once a week, asks GitHub for the latest release; if there is a newer version, offers to download it.
@MainActor
enum UpdateChecker {
    private static let lastKey = "update.lastCheck"
    private static let api = URL(string: "https://api.github.com/repos/jonathansfp/copypaste/releases/latest")!
    static let downloadURL = URL(string: "https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-macOS.dmg")!
    private static var timer: Timer?

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
            alert(L("Nova versão do CopyPaste: %@", latest),
                  L("Você está na %@. Baixe a nova versão, abra o arquivo e arraste o CopyPaste para Aplicativos, substituindo o atual. Seu histórico e as configurações são mantidos.", current) + notes,
                  update: true)
        } else if manual {
            alert(L("Você já tem a versão mais recente"), "CopyPaste \(current).", update: false)
        }
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
            a.addButton(withTitle: L("Baixar atualização"))
            a.addButton(withTitle: L("Ver novidades"))
            a.addButton(withTitle: L("Depois"))
            switch a.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(downloadURL)
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
