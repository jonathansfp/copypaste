import AppKit
import ApplicationServices

enum PasteService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Simulates ⌘V in the frontmost app.
    static func sendPaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                        state: .eventSuppressionStateSuppressionInterval)
        let v = CGKeyCode(9) // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// Screen rect (Cocoa coordinates) of the text caret in the focused app, when available.
    static func caretRect() -> NSRect? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let range = rangeValue else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &boundsValue) == .success,
              let bounds = boundsValue, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0,
              rect.origin.x > 0 || rect.origin.y > 0 else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.origin.x, y: primaryHeight - rect.origin.y - rect.height,
                      width: max(rect.width, 1), height: rect.height)
    }

    /// Waits (up to ~1.5 s) until the user lets go of ⌘⌥⇧⌃, so a synthetic ⌘V/⌘C is not mixed with them.
    static func waitForModifiersReleased() async {
        let mask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        for _ in 0..<30 {
            if NSEvent.modifierFlags.intersection(mask).isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Text selected in the focused app: via Accessibility, or by sending ⌘C and restoring the clipboard.
    @MainActor
    static func selectedText() async -> String? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let ref = focused, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(ref as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty {
                return text
            }
        }
        // Fallback for apps without AX text (browsers, Electron): copy and restore.
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item -> [(NSPasteboard.PasteboardType, Data)] in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        } ?? []
        let before = pb.changeCount
        let src = CGEventSource(stateID: .combinedSessionState)
        let c = CGKeyCode(8) // kVK_ANSI_C
        let down = CGEvent(keyboardEventSource: src, virtualKey: c, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: c, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if pb.changeCount != before { break }
        }
        guard pb.changeCount != before else { return nil }
        let text = pb.string(forType: .string)
        pb.clearContents()
        if !saved.isEmpty {
            let items = saved.map { pairs -> NSPasteboardItem in
                let it = NSPasteboardItem()
                for (t, d) in pairs { it.setData(d, forType: t) }
                return it
            }
            pb.writeObjects(items)
        }
        return (text?.isEmpty ?? true) ? nil : text
    }
}
