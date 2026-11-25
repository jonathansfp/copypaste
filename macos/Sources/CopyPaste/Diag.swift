import AppKit
import ScreenCaptureKit

/// Registro de diagnóstico em ~/Library/Application Support/CopyPaste/diagnostico.log (máx. ~200 KB).
enum Diag {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyPaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostico.log")
    }()
    private static let queue = DispatchQueue(label: "copypaste.diag")
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    static func log(_ msg: String) {
        let line = "\(fmt.string(from: Date())) \(msg)\n"
        NSLog("CopyPaste: %@", msg)
        queue.async {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > 200_000 {
                try? FileManager.default.removeItem(at: url)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    /// `CopyPaste --diagnose`: testa permissão e captura, grava no log e encerra.
    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--diagnose") else { return }
        log("diagnose: início, pid=\(ProcessInfo.processInfo.processIdentifier), bundle=\(Bundle.main.bundlePath)")
        log("diagnose: CGPreflightScreenCaptureAccess=\(CGPreflightScreenCaptureAccess())")
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                log("diagnose: SCShareableContent ok, telas=\(content.displays.count), janelas=\(content.windows.count)")
                let shots = try await ScreenGrabber.captureAll()
                for s in shots { log("diagnose: captura ok \(s.image.width)x\(s.image.height) escala=\(s.scale)") }
                // --save <arquivo.png>: grava a tela principal (útil para conferir a interface).
                let args = CommandLine.arguments
                if let i = args.firstIndex(of: "--save"), i + 1 < args.count, let first = shots.first(where: { $0.screen == NSScreen.screens.first }) ?? shots.first {
                    let rep = NSBitmapImageRep(cgImage: first.image)
                    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
                    log("diagnose: salvo em \(args[i + 1])")
                }
            } catch {
                log("diagnose: ERRO \(error) (\((error as NSError).domain) \((error as NSError).code))")
            }
            log("diagnose: fim")
            exit(0)
        }
        NSApplication.shared.run()
    }
}
