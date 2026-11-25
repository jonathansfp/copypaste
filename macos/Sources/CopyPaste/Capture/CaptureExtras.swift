import AppKit
import SwiftUI
import Vision

// MARK: - Toast

/// Small HUD message at the bottom of the screen ("Copiado", "Salvo"…).
@MainActor
enum Toast {
    private static var window: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String = "checkmark.circle.fill", duration: TimeInterval = 1.8) {
        hideWork?.cancel()
        window?.orderOut(nil)
        let view = HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .floatingBar()
        .fixedSize()

        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let screen = ScreenGrabber.screenUnderMouse()
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 90, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar + 1
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        window = p
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) {
                p.orderOut(nil)
                if window === p { window = nil }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

// MARK: - OCR

enum TextRecognizer {
    static func recognize(_ image: NSImage, completion: @escaping (String) -> Void) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { completion(""); return }
        let request = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pt-BR", "en-US", "es-ES"]
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cg).perform([request])
        }
    }
}

// MARK: - Pinned capture

/// Keeps a capture floating above other windows (reference while you work).
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []
    private let image: NSImage

    static func pin(_ image: NSImage, at frame: CGRect) {
        let w = PinWindow(image: image, frame: frame)
        open.append(w)
        w.orderFrontRegardless()
        w.makeKey()
    }

    init(image: NSImage, frame: CGRect) {
        self.image = image
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        level = .floating
        isMovableByWindowBackground = true
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        aspectRatio = image.size
        isReleasedWhenClosed = false
        let iv = PinImageView(frame: CGRect(origin: .zero, size: frame.size))
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.autoresizingMask = [.width, .height]
        iv.wantsLayer = true
        iv.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        iv.layer?.borderWidth = 1
        iv.owner = self
        contentView = iv
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { closePin(); return }
        if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "c" { ImageOutput.copy(image); Toast.show("Copiada"); return }
        super.keyDown(with: e)
    }

    override func scrollWheel(with e: NSEvent) {
        alphaValue = min(1, max(0.25, alphaValue + e.scrollingDeltaY * 0.01))
    }

    func closePin() {
        orderOut(nil)
        PinWindow.open.removeAll { $0 === self }
    }

    fileprivate func menu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Copiar", action: #selector(copyImage), keyEquivalent: "c").target = self
        m.addItem(withTitle: "Salvar na pasta", action: #selector(saveImage), keyEquivalent: "s").target = self
        m.addItem(withTitle: "Abrir no quadro", action: #selector(openBoard), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Fechar", action: #selector(closeAction), keyEquivalent: "")
            .target = self
        return m
    }

    @objc private func copyImage() { ImageOutput.copy(image); Toast.show("Copiada") }
    @objc private func saveImage() { if let u = ImageOutput.saveToFolder(image) { Toast.show("Salva: \(u.lastPathComponent)") } }
    @objc private func openBoard() { BoardController.shared.open(with: image) }
    @objc private func closeAction() { closePin() }
}

private final class PinImageView: NSImageView {
    weak var owner: PinWindow?
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { owner?.closePin(); return }
        window?.performDrag(with: e)
    }
    override func menu(for event: NSEvent) -> NSMenu? { owner?.menu() }
}
