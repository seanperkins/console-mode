import AppKit
import SwiftUI

@MainActor
final class ConsolePanel: NSPanel {
    private let model: NoteListModel
    private let effectView = NSVisualEffectView()
    private var hostingView: NSHostingView<ConsoleRootView>!
    private var noteInputField: NoteInputField.Coordinator.NSTextFieldBox?
    private(set) var isPanelVisible = false

    init(model: NoteListModel) {
        self.model = model
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
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

        configureEffectView()

        let rootView = ConsoleRootView(
            model: model,
            onExpandedChange: { [weak self] in
                guard let self, self.isPanelVisible else { return }
                self.refreshFrame(on: ScreenLocator.screenForMouse(), animated: true)
            },
            onInputFieldCreated: { [weak self] field in
                self?.noteInputField = field
            }
        )
        hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(hostingView)
        contentView = effectView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
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
        updateEffectMaterial()
        applyFrame(on: screen, animated: true, appearing: true)
        makeKeyAndOrderFront(nil)
        isPanelVisible = true
        model.requestInputFocus()
        focusInputField()
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

    private func configureEffectView() {
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = PanelGeometry.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
    }

    private func updateEffectMaterial() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            effectView.material = .windowBackground
            effectView.blendingMode = .withinWindow
        } else {
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
        }
    }

    private func focusInputField() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let field = self.noteInputField?.field else { return }
            self.makeKey()
            self.makeFirstResponder(field)
        }
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let metrics = ScreenLocator.metrics(for: screen)
        return PanelGeometry.frame(
            screen: metrics,
            expanded: model.expanded,
            visibleRowCount: model.visibleRowCount
        )
    }

    private func applyFrame(on screen: NSScreen, animated: Bool, appearing: Bool? = nil) {
        let target = targetFrame(on: screen)

        if animated, appearing == true {
            var start = target
            start.origin.y += PanelGeometry.dropOffset
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
    @Bindable var model: NoteListModel
    let onExpandedChange: () -> Void
    let onInputFieldCreated: (NoteInputField.Coordinator.NSTextFieldBox) -> Void

    var body: some View {
        ConsoleView(model: model, onInputFieldCreated: onInputFieldCreated)
            .onChange(of: model.expanded) { _, _ in
                onExpandedChange()
            }
            .onChange(of: model.notes.count) { _, _ in
                onExpandedChange()
            }
    }
}
