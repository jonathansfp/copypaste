import AppKit
import AVFoundation
import ScreenCaptureKit

/// Screen + audio recording with ScreenCaptureKit's built-in recorder (encodes in hardware, low CPU).
@MainActor
final class ScreenRecorder: NSObject, ObservableObject {
    static let shared = ScreenRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?

    private var stream: SCStream?
    private var recordingOutput: AnyObject?
    private var fileURL: URL?
    private var border: NSWindow?
    private let sink = DiscardOutput()
    private let queue = DispatchQueue(label: "copypaste.record", qos: .userInitiated)

    static var isSupported: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Hotkey: first press chooses the area, second press stops.
    func toggleFromHotKey() {
        if isRecording { stop() } else { CaptureController.shared.start(mode: .record) }
    }

    func start(screen: NSScreen, rect: CGRect?, mic: Bool, systemAudio: Bool) {
        guard #available(macOS 15.0, *) else {
            Toast.show(L("Gravação de tela requer macOS 15 ou mais recente"), symbol: "exclamationmark.triangle", duration: 3)
            return
        }
        guard !isRecording else { return }
        Task { @MainActor in
            var useMic = mic
            if mic {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if !granted {
                    useMic = false
                    Toast.show(L("Sem permissão do microfone: gravando sem a sua voz"), symbol: "mic.slash", duration: 3)
                }
            }
            do {
                try await begin(screen: screen, rect: rect, mic: useMic, systemAudio: systemAudio)
            } catch {
                NSLog("CopyPaste: gravação falhou: \(error)")
                cleanup()
                Toast.show(L("Não foi possível gravar: %@", error.localizedDescription), symbol: "exclamationmark.triangle", duration: 4)
            }
        }
    }

    @available(macOS 15.0, *)
    private func begin(screen: NSScreen, rect: CGRect?, mic: Bool, systemAudio: Bool) async throws {
        guard let display = try await ScreenGrabber.display(for: screen) else { throw RecorderError.noDisplay }
        let s = AppSettings.shared

        if let rect { showBorder(around: rect) }
        // Exclude the dashed border (and only it): drawings from the board are recorded.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let borderID = border.map { CGWindowID($0.windowNumber) }
        let excluded = content.windows.filter { $0.windowID == borderID }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        var size = CGSize(width: display.width, height: display.height)
        if let rect {
            let sf = screen.frame
            let local = CGRect(x: rect.minX - sf.minX, y: sf.maxY - rect.maxY, width: rect.width, height: rect.height)
            cfg.sourceRect = local
            size = local.size
        }
        cfg.width = (Int(size.width * scale) / 2) * 2
        cfg.height = (Int(size.height * scale) / 2) * 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(15, s.recordFPS)))
        cfg.showsCursor = true
        cfg.showMouseClicks = s.recordShowClicks
        cfg.queueDepth = 6
        cfg.capturesAudio = systemAudio
        cfg.excludesCurrentProcessAudio = true
        cfg.captureMicrophone = mic

        let stream = SCStream(filter: filter, configuration: cfg, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: queue)
        if systemAudio { try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: queue) }
        if mic { try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: queue) }

        try FileManager.default.createDirectory(at: s.recordURL, withIntermediateDirectories: true)
        let url = s.recordURL.appendingPathComponent(ImageOutput.fileName(prefix: L("Gravação"), ext: "mov"))
        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = url
        rc.outputFileType = .mov
        rc.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: rc, delegate: sink)
        try stream.addRecordingOutput(output)

        sink.onFinish = { [weak self] error in
            DispatchQueue.main.async { self?.didFinish(error: error) }
        }
        try await stream.startCapture()
        self.stream = stream
        self.recordingOutput = output
        self.fileURL = url
        isRecording = true
        startedAt = Date()
        Toast.show(L("Gravando… pare com %@ ou pelo ícone na barra", s.hotKey(for: .record)?.display ?? L("o menu")), symbol: "record.circle", duration: 2.5)
    }

    func stop() {
        guard isRecording, let stream else { return }
        Task { @MainActor in
            try? await stream.stopCapture()
            // SCRecordingOutput finishes writing asynchronously; didFinish() is called by the delegate.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if self?.stream != nil { self?.didFinish(error: nil) }
            }
        }
    }

    private func didFinish(error: Error?) {
        let url = fileURL
        cleanup()
        if let error {
            Toast.show(L("Erro na gravação: %@", error.localizedDescription), symbol: "exclamationmark.triangle", duration: 4)
        } else if let url, FileManager.default.fileExists(atPath: url.path) {
            Toast.show(L("Gravação salva: %@", url.lastPathComponent), symbol: "film", duration: 3)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func cleanup() {
        stream = nil
        recordingOutput = nil
        fileURL = nil
        isRecording = false
        startedAt = nil
        sink.onFinish = nil
        border?.orderOut(nil)
        border = nil
    }

    // MARK: Area border

    private func showBorder(around rect: CGRect) {
        let w = NSWindow(contentRect: rect.insetBy(dx: -3, dy: -3), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.level = .statusBar
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.isReleasedWhenClosed = false
        let v = NSView()
        v.wantsLayer = true
        v.layer?.borderColor = NSColor.systemRed.cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 2
        w.contentView = v
        w.orderFrontRegardless()
        border = w
    }

    enum RecorderError: LocalizedError {
        case noDisplay
        var errorDescription: String? { L("tela não encontrada") }
    }
}

/// Receives (and drops) samples: SCStream needs an output, the recording output does the writing.
final class DiscardOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFinish: ((Error?) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFinish?(error)
    }
}

@available(macOS 15.0, *)
extension DiscardOutput: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        onFinish?(nil)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        onFinish?(error)
    }
}
