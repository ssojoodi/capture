import AppKit

enum AppMenu {
    static let appName = "Capture"

    static func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let fileItem = NSMenuItem()
        let editItem = NSMenuItem()
        main.addItem(appItem)
        main.addItem(fileItem)
        main.addItem(editItem)

        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Canvas", action: #selector(AppDelegate.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open...", action: #selector(MainWindowController.openImage(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(MainWindowController.save(_:)), keyEquivalent: "s")
        let saveAsItem = fileMenu.addItem(withTitle: "Save As...", action: #selector(MainWindowController.saveAs(_:)), keyEquivalent: "s")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Export JPG...", action: #selector(MainWindowController.exportJPG(_:)), keyEquivalent: "e")
        fileItem.submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        let pasteItem = editMenu.addItem(withTitle: "Paste Image", action: #selector(MainWindowController.pasteImage(_:)), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.command, .shift]
        let copyItem = editMenu.addItem(withTitle: "Copy Image", action: #selector(MainWindowController.copyFlattenedImage(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(withTitle: "Duplicate", action: #selector(MainWindowController.duplicateSelected(_:)), keyEquivalent: "d")
        editMenu.addItem(withTitle: "Delete", action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: "\u{8}")
        editItem.submenu = editMenu

        return main
    }
}
