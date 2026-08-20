import AppKit
import KeyboardShortcuts
import os
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let signposter = OSSignposter(subsystem: "com.seanperkins.ConsoleMode", category: "Summon")

    private var store: NoteStore!
    private var model: NoteListModel!
    private var panel: ConsolePanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
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
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Console Mode", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func installHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleConsole) { [weak self] in
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
            let state = signposter.beginInterval("Summon")
            panel.show(on: screen)
            installDismissMonitors()
            signposter.endInterval("Summon", state)
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
            let view = SettingsView()
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Console Mode Settings"
            window.styleMask = [.titled, .closable]
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
