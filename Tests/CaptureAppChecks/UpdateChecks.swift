import AppKit

extension WindowChecks {
    static func runUpdateChecks() {
        let suite = "Capture.UpdateChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 10_000)
        var active = true
        var requests: [URLRequest] = []
        var callbacks: [(Result<Data, Error>) -> Void] = []
        var shown: [UpdateController.Presentation] = []
        var opened: [URL] = []
        let config = UpdateConfiguration(manifestURL: URL(string: "https://updates.example.test/current.json")!,
            downloadURL: URL(string: "https://downloads.example.test/App.dmg")!,
            releaseNotesURL: URL(string: "https://example.test/changes")!,
            automaticCheckInterval: 60, requestTimeout: 3)
        let fetch: UpdateController.Fetch = { request, completion in requests.append(request); callbacks.append(completion) }
        func controller(build: String? = "4") -> UpdateController {
            UpdateController(configuration: config, defaults: defaults, installedVersion: "2026.10.10", installedBuild: build,
                now: { date }, isActive: { active }, fetch: fetch,
                openURL: { opened.append($0); return true }, presentationHandler: { shown.append($0) })
        }
        let updater = controller()
        func reply(_ result: Result<Data, Error>) {
            callbacks.removeFirst()(result)
            let deadline = Date().addingTimeInterval(2)
            while updater.isChecking && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            precondition(!updater.isChecking)
        }
        func manifest(_ build: String, version: String = "2026.10.10") -> Result<Data, Error> {
            .success(try! JSONSerialization.data(withJSONObject: ["build": build, "version": version]))
        }
        precondition(!updater.automaticEnabled)
        updater.applicationDidBecomeActive()
        precondition(requests.isEmpty)
        updater.setAutomaticEnabled(true)
        precondition(requests.count == 1 && shown.isEmpty)
        precondition(requests[0].url == config.manifestURL && requests[0].timeoutInterval == 3)
        precondition(requests[0].cachePolicy == .reloadRevalidatingCacheData)
        reply(manifest("4"))
        precondition(shown.isEmpty)
        updater.applicationDidBecomeActive()
        precondition(requests.count == 1)
        date = date.addingTimeInterval(59)
        updater.applicationDidBecomeActive()
        precondition(requests.count == 1)
        date = date.addingTimeInterval(1)
        updater.applicationDidBecomeActive()
        precondition(requests.count == 2)
        updater.checkForUpdates(nil) // Upgrade the in-flight automatic request to manual.
        precondition(requests.count == 2 && shown.last == .checking)
        reply(manifest("5"))
        precondition(shown.last == .available(UpdateRelease(version: "2026.10.10", build: "5")))
        let shownCount = shown.count
        date = date.addingTimeInterval(60)
        updater.applicationDidBecomeActive()
        reply(manifest("5"))
        precondition(shown.count == shownCount, "Automatic notifications repeat only for a new build")
        updater.checkForUpdates(nil)
        precondition(requests.count == 4, "Manual checks bypass the interval")
        reply(manifest("3"))
        precondition(shown.last == .current)
        updater.download(nil); updater.releaseNotes(nil)
        precondition(opened == [config.downloadURL, config.releaseNotesURL])
        updater.checkForUpdates(nil)
        reply(.success(Data("not JSON".utf8)))
        guard case .failure = shown.last! else { preconditionFailure("Malformed JSON must report an error") }
        updater.checkForUpdates(nil)
        reply(manifest("-1"))
        guard case .failure = shown.last! else { preconditionFailure("Invalid builds must report an error") }
        updater.checkForUpdates(nil)
        reply(.failure(URLError(.timedOut)))
        guard case .failure = shown.last! else { preconditionFailure("Manual timeout must be visible") }
        let failedCount = shown.count
        date = date.addingTimeInterval(60)
        updater.applicationDidBecomeActive()
        reply(.failure(URLError(.notConnectedToInternet)))
        precondition(shown.count == failedCount)
        let attempts = requests.count
        updater.applicationDidBecomeActive()
        precondition(requests.count == attempts, "Automatic errors must still be throttled")
        let restored = controller()
        precondition(restored.automaticEnabled && !restored.automaticCheckDue, "Preferences and attempt time persist across controller lifetimes")
        date = date.addingTimeInterval(60)
        active = false
        updater.applicationDidResignActive()
        updater.applicationDidBecomeActive()
        precondition(requests.count == attempts)
        active = true
        updater.applicationDidBecomeActive()
        active = false
        reply(manifest("6"))
        precondition(shown.count == failedCount, "Automatic presentation is deferred while inactive")
        active = true
        updater.applicationDidBecomeActive()
        precondition(shown.last == .available(UpdateRelease(version: "2026.10.10", build: "6")))
        date = date.addingTimeInterval(60)
        updater.applicationDidBecomeActive()
        updater.setAutomaticEnabled(false)
        let beforeDisabledReply = shown.count
        reply(manifest("7"))
        precondition(shown.count == beforeDisabledReply)
        precondition(!updater.automaticEnabled)
        let invalid = controller(build: nil)
        let beforeInvalid = requests.count
        invalid.checkForUpdates(nil)
        precondition(requests.count == beforeInvalid)
        guard case .failure = shown.last! else { preconditionFailure("Missing installed build must not report current") }
        let menuItem = NSMenuItem(title: "Automatically Check for Updates", action: #selector(UpdateController.toggleAutomaticChecks(_:)), keyEquivalent: "")
        precondition(updater.validateMenuItem(menuItem) && menuItem.state == .off)
        updater.setAutomaticEnabled(true)
        precondition(updater.validateMenuItem(menuItem) && menuItem.state == .on)
        updater.setAutomaticEnabled(false)
        let appMenu = AppMenu.makeMenu().items.first!.submenu!
        precondition(appMenu.items.contains { $0.action == #selector(AppDelegate.checkForUpdates(_:)) })
        let response = HTTPURLResponse(url: config.manifestURL, statusCode: 503, httpVersion: nil, headerFields: nil)!
        do {
            _ = try UpdateController.validateResponse(data: Data(), response: response)
            preconditionFailure("HTTP failures must not be accepted")
        } catch { }
        let ok = HTTPURLResponse(url: config.manifestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        do {
            _ = try UpdateController.validateResponse(data: Data(count: 65 * 1024), response: ok)
            preconditionFailure("Oversized manifests must not be accepted")
        } catch { }
        // Exercise native UI from a local mock; never publish a fictitious release.
        let ui = UpdateController(configuration: config, defaults: defaults, installedVersion: "2026.10.10", installedBuild: "4",
            isActive: { true }, fetch: { _, completion in completion(manifest("5", version: "Preview")) }, openURL: { _ in true })
        let keyWindow = NSApp.keyWindow
        let firstResponder = keyWindow?.firstResponder
        ui.checkForUpdates(nil)
        precondition(NSApp.modalWindow == nil && NSApp.keyWindow === keyWindow)
        precondition(keyWindow?.firstResponder === firstResponder)
        let panel = ui.panel!
        panel.contentView!.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.close()
        print("PASS: configurable update URLs, versions, opt-in, persistence, daily boundary, manual bypass, coalescing, errors, inactive deferral and browser routing")
    }
}
