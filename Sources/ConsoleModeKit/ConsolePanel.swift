import AppKit
import SwiftUI

@MainActor
final class ConsolePanel: NSPanel {
    private let shell: ConsoleShell
    private var hostingView: NSHostingView<ConsoleRootView>!
    private(set) var isPanelVisible = false

    init(shell: ConsoleShell) {
        self.shell = shell
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let rootView = ConsoleRootView(shell: shell) { [weak self] in
            guard let self, self.isPanelVisible else { return }
            self.refreshFrame(on: ScreenLocator.screenForMouse(), animated: true)
        }
        hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView = NSView(frame: .zero)
        contentView?.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
        ])
    }

    override var canBecomeKey: Bool { true }

    func prewarm(on screen: NSScreen) {
        applyFrame(on: screen, animated: false)
        alphaValue = 0
        orderOut(nil)
        isPanelVisible = false
    }

    func show(on screen: NSScreen) {
        applyFrame(on: screen, animated: true, appearing: true)
        makeKeyAndOrderFront(nil)
        isPanelVisible = true
        // Only the notes tab has a text field to focus.
        if shell.activeTab == .notes {
            shell.notes.requestInputFocus()
        }
    }

    /// Command shortcuts must be intercepted here: the panel is nonactivating, so
    /// SwiftUI key handling never sees them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        switch characters.lowercased() {
        case "1":
            shell.select(.notes)
            focusIfNeeded()
            return true
        case "2":
            shell.select(.usage)
            return true
        case "r":
            Task { await shell.usage.refresh() }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌃Tab cycles tabs; plain Tab still walks the input bar's key view loop.
        if flags.contains(.control), event.keyCode == 48 {
            shell.cycleTab()
            focusIfNeeded()
            return
        }
        super.keyDown(with: event)
    }

    private func focusIfNeeded() {
        guard shell.activeTab == .notes else { return }
        shell.notes.requestInputFocus()
    }

    func hide() {
        guard isPanelVisible else { return }
        animateDismiss { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            self.isPanelVisible = false
        }
    }

    func refreshFrame(on screen: NSScreen, animated: Bool) {
        guard isPanelVisible else { return }
        let target = targetFrame(on: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let metrics = ScreenLocator.metrics(for: screen)
        return PanelGeometry.frame(
            screen: metrics,
            tab: shell.activeTab,
            expanded: shell.notes.expanded,
            visibleRowCount: shell.visibleRowCount,
            providerCount: shell.usageLineCount
        )
    }

    private func applyFrame(on screen: NSScreen, animated: Bool, appearing: Bool? = nil) {
        let target = targetFrame(on: screen)

        if animated, appearing == true {
            var start = target
            start.origin.y -= PanelGeometry.dropOffset
            setFrame(start, display: true)
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(target, display: true)
                self.animator().alphaValue = 1
            }
        } else if !animated {
            setFrame(target, display: true)
            alphaValue = 1
        }
    }

    private func animateDismiss(completion: @escaping @MainActor () -> Void) {
        var end = frame
        end.origin.y += PanelGeometry.dropOffset
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(end, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                completion()
            }
        })
    }
}

@MainActor
struct ConsoleRootView: View {
    @Bindable var shell: ConsoleShell
    let onLayoutChange: () -> Void

    var body: some View {
        ConsoleView(shell: shell)
            .onChange(of: shell.notes.expanded) { _, _ in onLayoutChange() }
            .onChange(of: shell.notes.notes.count) { _, _ in onLayoutChange() }
            // Tabs and provider count both change the card height.
            .onChange(of: shell.activeTab) { _, _ in onLayoutChange() }
            .onChange(of: shell.usageLineCount) { _, _ in
                // Provider count sets the resting height, so the notes tab's row
                // capacity has to follow it.
                shell.syncCollapsedCapacity()
                onLayoutChange()
            }
    }
}
