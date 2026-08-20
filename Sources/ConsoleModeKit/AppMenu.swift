import AppKit

/// Minimal menu bar so Edit shortcuts (⌘V paste, etc.) reach the key field via the responder chain.
@MainActor
enum AppMenu {
    static func install(
        settingsTarget: NSObject,
        settingsAction: Selector,
        quitTarget: NSObject,
        quitAction: Selector
    ) {
        NSApp.mainMenu = makeMainMenu(
            settingsTarget: settingsTarget,
            settingsAction: settingsAction,
            quitTarget: quitTarget,
            quitAction: quitAction
        )
    }

    static func makeMainMenu(
        settingsTarget: NSObject,
        settingsAction: Selector,
        quitTarget: NSObject,
        quitAction: Selector
    ) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let settingsItem = NSMenuItem(title: "Settings…", action: settingsAction, keyEquivalent: ",")
        settingsItem.target = settingsTarget
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        let quitItem = NSMenuItem(title: "Quit \(appName)", action: quitAction, keyEquivalent: "q")
        quitItem.target = quitTarget
        appMenu.addItem(quitItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(responderItem("Undo", action: Selector("undo:"), key: "z"))
        editMenu.addItem(
            responderItem(
                "Redo",
                action: Selector("redo:"),
                key: "Z",
                modifiers: [.command, .shift]
            )
        )
        editMenu.addItem(.separator())
        editMenu.addItem(responderItem("Cut", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(responderItem("Copy", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(responderItem("Paste", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(responderItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))

        return mainMenu
    }

    private static func responderItem(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}
