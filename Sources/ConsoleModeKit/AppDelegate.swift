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
    private var usage: UsageMonitor!
    private var shell: ConsoleShell!
    private var panel: ConsolePanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let settingsWindowDelegate = SettingsWindowDelegate()
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var alertDismissTask: Task<Void, Never>?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenu.install(
            settingsTarget: self,
            settingsAction: #selector(openSettings),
            quitTarget: self,
            quitAction: #selector(quit)
        )

        do {
            store = try NoteStore.openDefault()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }

        model = NoteListModel(store: store)
        model.onAction = { [weak self] action in
            switch action {
            case .openSettings:
                self?.dismissConsole()
                self?.openSettings()
            case .quit:
                NSApp.terminate(nil)
            }
        }
        usage = UsageMonitor()
        usage.onAlert = { [weak self] alert in
            self?.presentUsageAlert(alert)
        }
        shell = ConsoleShell(notes: model, usage: usage)

        panel = ConsolePanel(shell: shell)
        usage.onDataChange = { [weak self] in
            guard let self else { return }
            self.shell.syncCollapsedCapacity()
            self.panel.updateLayout(on: ScreenLocator.screenForMouse(), animated: self.panel.isPanelVisible)
        }
        panel.prewarm(on: ScreenLocator.screenForMouse())

        installStatusItem()
        installHotkey()

        if UsageSettings.current.isEnabled {
            usage.start()
            observeSeverityForStatusItem()
        }

        Task { await ReminderScheduler.rescheduleAll(store: store) }
    }

    // MARK: - Usage alerts

    /// A crossing pops the console onto the usage tab briefly, then puts it back.
    /// Transient by design: the lasting signal is the menu bar tint.
    private func presentUsageAlert(_ alert: UsageAlert) {
        updateStatusItemAppearance()

        let seconds = UsageSettings.current.alertSeconds
        shell.select(.usage)
        if !panel.isPanelVisible {
            panel.show(on: ScreenLocator.screenForMouse())
            installDismissMonitors()
        }

        alertDismissTask?.cancel()
        alertDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.usage.clearAlert()
            // Leave it up if the user switched tabs, meaning they took over.
            if self.panel.isPanelVisible, self.shell.activeTab == .usage {
                self.dismissConsole()
            }
        }
    }

    /// Repaint the menu bar whenever the worst severity changes.
    private func observeSeverityForStatusItem() {
        withObservationTracking {
            _ = usage.worstSeverity
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusItemAppearance()
                self?.observeSeverityForStatusItem()
            }
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let severity = usage.worstSeverity
        let item = StatusItemAppearance.forSeverity(severity)
        item.apply(to: button)
        button.toolTip = severity > .healthy
            ? usage.rollup.first.map { "\($0.displayName): \(UsageAlert.format($0.remainingFraction ?? 0)) left" }
            : nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Same helper as the severity updates, so the template flag is set on
            // every path rather than only after the first usage poll.
            StatusItemAppearance.forSeverity(.healthy).apply(to: button)
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

        // A local monitor sees keyDown before the responder chain, so these reach
        // us even while the capture field holds focus.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isPanelVisible else { return event }
            let terminalActive = self.shell.activeTab == .terminal
            guard let action = ConsoleKeyBinding.action(for: event, terminalActive: terminalActive) else { return event }

            switch action {
            case .dismiss:
                self.dismissConsole()
            case .selectTab(let tab):
                self.shell.select(tab)
                if tab == .notes { self.model.requestInputFocus() }
            case .cycleTab:
                self.shell.cycleTab()
                if self.shell.activeTab == .notes { self.model.requestInputFocus() }
            case .refreshUsage:
                Task { await self.usage.refresh() }
            }
            // Swallowed: a bare digit must not also land in the text field.
            return nil
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
            let contentSize = NSSize(width: 520, height: 700)
            let hostingView = NSHostingView(rootView: SettingsView(shell: shell))
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
