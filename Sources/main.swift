import AppKit

let env = ProcessInfo.processInfo.environment

if let dir = env["OVERTEXT_README"] {
    MainActor.assumeIsolated { Snapshot.readme(to: dir) }
    exit(0)
}

if let dir = env["OVERTEXT_SNAPSHOT"] {
    MainActor.assumeIsolated { Snapshot.render(to: dir) }
    exit(0)
}

// второй экземпляр не запускаем
let me = Bundle.main.bundleIdentifier ?? "com.markdev.overtext"
if NSRunningApplication.runningApplications(withBundleIdentifier: me).count > 1 { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
