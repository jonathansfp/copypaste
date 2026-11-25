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
}
