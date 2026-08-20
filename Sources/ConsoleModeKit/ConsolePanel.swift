import AppKit
import SwiftUI

@MainActor
final class ConsolePanel: NSPanel {
    private let model: NoteListModel
    private var hostingView: NSHostingView<ConsoleRootView>!
    private(set) var isPanelVisible = false

    init(model: NoteListModel) {
        self.model = model
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

        let rootView = ConsoleRootView(model: model) { [weak self] in
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
        model.requestInputFocus()
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
            expanded: model.expanded,
            visibleRowCount: model.visibleRowCount
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
    @Bindable var model: NoteListModel
    let onExpandedChange: () -> Void
    var body: some View {
        ConsoleView(model: model)
            .onChange(of: model.expanded) { _, _ in
                onExpandedChange()
            }
            .onChange(of: model.notes.count) { _, _ in
                onExpandedChange()
            }
    }
}
