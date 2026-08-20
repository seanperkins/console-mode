import AppKit
import Testing

@testable import ConsoleModeKit

@MainActor
struct AppMenuTests {
    @Test func editMenuWiresPasteToResponderChain() {
        let menu = AppMenu.makeMainMenu(
            settingsTarget: NSObject(),
            settingsAction: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            quitTarget: NSObject(),
            quitAction: #selector(NSApplication.terminate(_:))
        )

        let editMenu = menu.item(withTitle: "Edit")?.submenu
        let paste = editMenu?.item(withTitle: "Paste")

        #expect(paste != nil)
        #expect(paste?.keyEquivalent == "v")
        #expect(paste?.keyEquivalentModifierMask == .command)
        #expect(paste?.target == nil)
        #expect(paste?.action == #selector(NSText.paste(_:)))
    }

    @Test func appMenuIncludesQuitAndSettings() {
        let menu = AppMenu.makeMainMenu(
            settingsTarget: NSObject(),
            settingsAction: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            quitTarget: NSObject(),
            quitAction: #selector(NSApplication.terminate(_:))
        )

        let appMenu = menu.items.first?.submenu
        let settings = appMenu?.item(withTitle: "Settings…")
        let quit = appMenu?.items.last

        #expect(settings?.keyEquivalent == ",")
        #expect(quit?.keyEquivalent == "q")
        #expect(quit?.action == #selector(NSApplication.terminate(_:)))
    }
}
