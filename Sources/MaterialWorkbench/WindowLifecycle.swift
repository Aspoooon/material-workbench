import SwiftUI
import AppKit

/// Keep one main window alive when its red close button is used. The shared
/// model and running jobs remain owned by the App, not by window visibility.
@MainActor final class WorkbenchDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var model: WorkbenchModel?
    weak var mainWindow: NSWindow?
    var openMainWindow: (() -> Void)?
    private var opening = false

    func register(_ window: NSWindow) {
        mainWindow = window
        opening = false
        window.identifier = NSUserInterfaceItemIdentifier("MaterialWorkbench.main")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func restoreMainWindow() {
        guard let window = mainWindow, NSApp.windows.contains(where: { $0 === window }) else {
            if !opening { opening = true; openMainWindow?() }
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        restoreMainWindow()
        sender.activate(ignoringOtherApps: true)
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if mainWindow == nil || mainWindow?.isVisible == false || mainWindow?.isMiniaturized == true {
            restoreMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.running else { return .terminateNow }
        if model.module != .rename { model.runner.cancel() }
        Task {
            while model.running { try? await Task.sleep(for: .milliseconds(100)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MainWindowProbe: NSViewRepresentable {
    let register: (NSWindow) -> Void
    final class Probe: NSView {
        var register: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { register?(window) }
        }
    }
    func makeNSView(context: Context) -> Probe {
        let view = Probe(); view.register = register; return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        view.register = register
        if let window = view.window { register(window) }
    }
}
