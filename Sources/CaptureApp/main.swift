import AppKit

let app = NSApplication.shared
app.appearance = NSAppearance(named: .aqua)
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = AppMenu.makeMenu()
app.run()
