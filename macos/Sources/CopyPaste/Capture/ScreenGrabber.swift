import AppKit
import ScreenCaptureKit

struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
    /// Image pixels per screen point.
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

/// Screen pixels via ScreenCaptureKit + window geometry for snapping.
@MainActor
enum ScreenGrabber {
    private static var cachedDisplays: [SCDisplay] = []

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks for Screen Recording permission. Returns false (and guides the user) when not yet granted.
    @discardableResult
    static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Permita a gravação de tela")
        alert.informativeText = L("Para capturar e gravar a tela, ative o CopyPaste em Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema. Depois feche e abra o CopyPaste de novo.")
        alert.addButton(withTitle: L("Abrir Ajustes"))
        alert.addButton(withTitle: L("Agora não"))
        if alert.runModal() == .alertFirstButtonReturn { openSettings() }
        return false
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func displays(refresh: Bool = false) async throws -> [SCDisplay] {
        if refresh || cachedDisplays.isEmpty {
            cachedDisplays = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
        }
        return cachedDisplays
    }

    static func display(for screen: NSScreen) async throws -> SCDisplay? {
        let id = displayID(of: screen)
        if let d = try await displays().first(where: { $0.displayID == id }) { return d }
        return try await displays(refresh: true).first { $0.displayID == id }
    }

    /// Freezes every screen at full Retina resolution.
    static func captureAll() async throws -> [FrozenScreen] {
        var out: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let d = try await display(for: screen) else { continue }
            let img = try await capture(display: d, screen: screen)
            out.append(FrozenScreen(screen: screen, image: img))
        }
        return out
    }

    static func capture(display: SCDisplay, screen: NSScreen, excludingSelf: Bool = false) async throws -> CGImage {
        var filter = SCContentFilter(display: display, excludingWindows: [])
        if excludingSelf {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
        }
        let c = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        c.width = Int(CGFloat(display.width) * scale)
        c.height = Int(CGFloat(display.height) * scale)
        c.showsCursor = false
        c.captureResolution = .best
        c.colorSpaceName = CGColorSpace.sRGB
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: c)
    }

    /// On-screen app windows (front to back) in global Cocoa coordinates.
    static func windowRects() -> [CGRect] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? pid_t) != myPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  r.width >= 40, r.height >= 40 else { return nil }
            return CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
        }
    }
}

// MARK: - Image output

@MainActor
enum ImageOutput {
    static func data(_ image: NSImage, format: CaptureFormat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = image.size
        switch format {
        case .png: return rep.representation(using: .png, properties: [:])
        case .jpg: return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }

    static func copy(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = data(image, format: .png) {
            pb.declareTypes([.png, .tiff], owner: nil)
            pb.setData(png, forType: .png)
            if let tiff = image.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        } else {
            pb.writeObjects([image])
        }
    }

    static func fileName(prefix: String? = nil, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: AppLanguage.current.localeTag)
        f.dateFormat = L("yyyy-MM-dd 'às' HH.mm.ss")
        return "\(prefix ?? L("Captura")) \(f.string(from: Date())).\(ext)"
    }

    @discardableResult
    static func saveToFolder(_ image: NSImage) -> URL? {
        let s = AppSettings.shared
        let dir = s.captureSaveURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(ext: s.captureFormat.rawValue))
        guard let d = data(image, format: s.captureFormat), (try? d.write(to: url)) != nil else {
            Toast.show(L("Não foi possível salvar em %@", dir.path), symbol: "exclamationmark.triangle")
            return nil
        }
        return url
    }

    static func saveAs(_ image: NSImage) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(ext: AppSettings.shared.captureFormat.rawValue)
        panel.allowedContentTypes = [.png, .jpeg]
        panel.directoryURL = AppSettings.shared.captureSaveURL
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let fmt: CaptureFormat = url.pathExtension.lowercased().hasPrefix("jp") ? .jpg : .png
        if let d = data(image, format: fmt) { try? d.write(to: url) }
        Toast.show(L("Salvo: %@", url.lastPathComponent), symbol: "checkmark.circle")
    }
}
