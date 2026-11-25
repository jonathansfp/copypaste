import AppKit

MainActor.assumeIsolated {
    SelfTest.runIfRequested()
    Diag.runIfRequested()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
