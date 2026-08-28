import AppKit

// Top-level code runs on the main thread but isn't statically MainActor;
// assumeIsolated bridges that for the AppKit bootstrap.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
