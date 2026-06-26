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
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open...", action: #selector(MainWindowController.openImage(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Export JPG...", action: #selector(MainWindowController.exportJPG(_:)), keyEquivalent: "e")
        fileItem.submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Paste", action: #selector(MainWindowController.pasteImage(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Copy", action: #selector(MainWindowController.copyFlattenedImage(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Delete", action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: "\u{8}")
        editItem.submenu = editMenu

        return main
    }
}
