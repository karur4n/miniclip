import AppKit
import ApplicationServices
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.karur4n.miniclip", category: "app")
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?
    private let popup = PopupPanel()
    private lazy var watcher = SelectionWatcher { [weak self] point in
        self?.selectionDidEnd(at: point)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startWatching()
            return
        }
        setIcon(trusted: false)
        log.error("アクセシビリティ権限がないため監視を始めない")
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.startWatching()
        }
    }

    private func startWatching() {
        setIcon(trusted: true)
        watcher.start()
        log.info("監視を開始")
    }

    private func selectionDidEnd(at point: NSPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self,
                  let raw = SelectionReader.read(),
                  let menu = Actions.menu(for: raw) else { return }
            popup.show(text: menu.text, actions: menu.actions, at: point)
        }
    }

    private func setIcon(trusted: Bool) {
        let name = trusted ? "text.cursor" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "MiniClip")
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
