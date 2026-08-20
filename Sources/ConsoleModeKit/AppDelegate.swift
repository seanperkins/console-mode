import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: NoteStore!
    private var model: NoteListModel!
    private var panel: ConsolePanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let settingsWindowDelegate = SettingsWindowDelegate()
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try NoteStore.openDefault()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }

        model = NoteListModel(store: store)
        panel = ConsolePanel(model: model)
        panel.prewarm(on: ScreenLocator.screenForMouse())

        installStatusItem()
        installHotkey()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Console Mode")
        }

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Console Mode", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func installHotkey() {
        KeyboardShortcuts.onKeyDown(for: .toggleConsole) { [weak self] in
            Task { @MainActor in
                self?.toggleConsole()
            }
        }
    }

    @objc private func toggleConsole() {
        let screen = ScreenLocator.screenForMouse()
        if panel.isPanelVisible {
            dismissConsole()
        } else {
            panel.show(on: screen)
            installDismissMonitors()
        }
    }

    private func dismissConsole() {
        removeDismissMonitors()
        panel.hide()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isPanelVisible else { return }
                let mouse = NSEvent.mouseLocation
                if !self.panel.frame.contains(mouse) {
                    self.dismissConsole()
                }
            }
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, self.panel.isPanelVisible {
                self.dismissConsole()
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let contentSize = NSSize(width: 460, height: 320)
            let hostingView = NSHostingView(rootView: SettingsView())
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            hostingView.autoresizingMask = [.width, .height]

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Console Mode Settings"
            window.contentView = hostingView
            window.contentMinSize = contentSize
            window.isReleasedWhenClosed = false
            window.delegate = settingsWindowDelegate
            window.center()
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
