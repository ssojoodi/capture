import AppKit

/// Change these values together when moving the website or changing check frequency.
struct UpdateConfiguration {
    var manifestURL = URL(string: "https://sojoodi.com/apps/Capture/release.json")!
    var downloadURL = URL(string: "https://sojoodi.com/apps/Capture/Capture.dmg")!
    var releaseNotesURL = URL(string: "https://sojoodi.com/apps/Capture/release-notes.html")!
    var automaticCheckInterval: TimeInterval = 24 * 60 * 60
    var requestTimeout: TimeInterval = 15
}

struct UpdateRelease: Decodable, Equatable {
    let version: String
    let build: String

    var buildNumber: Int? {
        guard !build.isEmpty, build.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(build), number > 0 else { return nil }
        return number
    }

    static func decode(_ data: Data) throws -> UpdateRelease {
        let release = try JSONDecoder().decode(Self.self, from: data)
        guard release.buildNumber != nil, !release.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              release.version.count < 100 else { throw UpdateFailure.invalidManifest }
        return release
    }
}

private enum UpdateFailure: LocalizedError {
    case invalidManifest, installedVersion, http
    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "The update information is invalid. Please try again later."
        case .installedVersion: return "Capture could not read its installed build number."
        case .http: return "The update server could not provide release information. Please try again later."
        }
    }
}

final class UpdateController: NSObject, NSMenuItemValidation {
    typealias Fetch = (URLRequest, @escaping (Result<Data, Error>) -> Void) -> Void
    enum Presentation: Equatable {
        case checking, available(UpdateRelease), current, failure(String)
    }
    private enum Key {
        static let automatic = "updates.automaticEnabled"
        static let attempt = "updates.lastAttempt"
        static let presented = "updates.lastPresentedBuild"
    }
    let configuration: UpdateConfiguration
    private let defaults: UserDefaults
    private let now: () -> Date
    private let isActive: () -> Bool
    private let fetch: Fetch
    private let openURL: (URL) -> Bool
    private let installed: UpdateRelease
    private let presentationHandler: ((Presentation) -> Void)?
    private var timer: Timer?
    private var pendingRelease: UpdateRelease?
    private var manualRequest = false
    private var suppressAutomaticResult = false
    private(set) var isChecking = false
    private(set) var presentation: Presentation?
    private(set) var panel: NSPanel?
    private var messageLabel: NSTextField?
    private var buttons: NSStackView?

    init(configuration: UpdateConfiguration = UpdateConfiguration(), defaults: UserDefaults = .standard,
         installedVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         installedBuild: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
         now: @escaping () -> Date = Date.init, isActive: @escaping () -> Bool = { NSApp.isActive },
         fetch: Fetch? = nil, openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
         presentationHandler: ((Presentation) -> Void)? = nil) {
        self.configuration = configuration
        self.defaults = defaults
        self.now = now
        self.isActive = isActive
        self.installed = UpdateRelease(version: installedVersion ?? "Unknown", build: installedBuild ?? "")
        self.openURL = openURL
        self.presentationHandler = presentationHandler
        self.fetch = fetch ?? { request, completion in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { completion(.failure(error)); return }
                completion(Result { try Self.validateResponse(data: data, response: response) })
            }.resume()
        }
        super.init()
    }

    deinit { timer?.invalidate() }

    static func validateResponse(data: Data?, response: URLResponse?) throws -> Data {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let data, data.count <= 64 * 1024 else { throw UpdateFailure.http }
        return data
    }

    var automaticEnabled: Bool { defaults.bool(forKey: Key.automatic) }
    var automaticCheckDue: Bool {
        guard let last = defaults.object(forKey: Key.attempt) as? Date else { return true }
        return now().timeIntervalSince(last) >= configuration.automaticCheckInterval
    }

    @objc func toggleAutomaticChecks(_ sender: Any?) { setAutomaticEnabled(!automaticEnabled) }

    func setAutomaticEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.automatic)
        if !enabled {
            timer?.invalidate(); timer = nil
            pendingRelease = nil
            suppressAutomaticResult = true
        } else {
            applicationDidBecomeActive()
        }
    }

    func applicationDidBecomeActive() {
        guard automaticEnabled, isActive() else { return }
        if let release = pendingRelease {
            pendingRelease = nil
            presentAutomatic(release)
        }
        if automaticCheckDue { check(manual: false) }
        else { schedule() }
    }

    func applicationDidResignActive() { timer?.invalidate(); timer = nil }

    @objc func checkForUpdates(_ sender: Any?) { check(manual: true) }

    func check(manual: Bool) {
        if !manual {
            guard automaticEnabled, isActive(), automaticCheckDue else { return }
        }
        if isChecking {
            if manual { manualRequest = true; present(.checking) }
            return
        }
        guard installed.buildNumber != nil else {
            if manual { present(.failure(UpdateFailure.installedVersion.localizedDescription)) }
            return
        }
        isChecking = true
        manualRequest = manual
        suppressAutomaticResult = false
        defaults.set(now(), forKey: Key.attempt)
        timer?.invalidate(); timer = nil
        if manual { present(.checking) }
        var request = URLRequest(url: configuration.manifestURL, cachePolicy: .reloadRevalidatingCacheData,
                                 timeoutInterval: configuration.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        fetch(request) { [weak self] result in
            if Thread.isMainThread { self?.receive(result) }
            else { DispatchQueue.main.async { self?.receive(result) } }
        }
    }

    private func receive(_ result: Result<Data, Error>) {
        let manual = manualRequest
        isChecking = false
        manualRequest = false
        defer { schedule() }
        do {
            let release = try UpdateRelease.decode(result.get())
            if release.buildNumber! > installed.buildNumber! {
                if manual {
                    pendingRelease = nil
                    present(.available(release))
                    defaults.set(release.build, forKey: Key.presented)
                } else if automaticEnabled && !suppressAutomaticResult {
                    if isActive() { presentAutomatic(release) }
                    else { pendingRelease = release }
                }
            } else if manual { present(.current) }
        } catch {
            if manual { present(.failure(error.localizedDescription)) }
        }
    }

    private func presentAutomatic(_ release: UpdateRelease) {
        guard defaults.string(forKey: Key.presented) != release.build else { return }
        present(.available(release))
        defaults.set(release.build, forKey: Key.presented)
    }

    private func schedule() {
        timer?.invalidate(); timer = nil
        guard automaticEnabled, isActive(), !isChecking, installed.buildNumber != nil else { return }
        let last = defaults.object(forKey: Key.attempt) as? Date ?? now()
        let delay = max(1, configuration.automaticCheckInterval - now().timeIntervalSince(last))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.applicationDidBecomeActive()
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAutomaticChecks(_:)) { item.state = automaticEnabled ? .on : .off }
        return true
    }

    @objc func download(_ sender: Any?) { open(configuration.downloadURL) }
    @objc func releaseNotes(_ sender: Any?) { open(configuration.releaseNotesURL) }
    @objc private func dismiss(_ sender: Any?) { panel?.orderOut(nil) }
    private func open(_ url: URL) {
        if !openURL(url) { present(.failure("Capture could not open your browser. Please try again.")) }
    }

    private func present(_ state: Presentation) {
        presentation = state
        if let presentationHandler { presentationHandler(state); return }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                                styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Capture Updates"
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.appearance = NSAppearance(named: .aqua)
            let label = NSTextField(wrappingLabelWithString: "")
            label.font = .systemFont(ofSize: 14)
            label.maximumNumberOfLines = 5
            let buttons = NSStackView()
            buttons.orientation = .horizontal
            buttons.spacing = 10
            let stack = NSStackView(views: [label, buttons])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 24
            stack.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -24),
                label.widthAnchor.constraint(equalTo: stack.widthAnchor),
                stack.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor)
            ])
            panel.center()
            self.panel = panel; messageLabel = label; self.buttons = buttons
        }
        for view in buttons!.arrangedSubviews { buttons!.removeArrangedSubview(view); view.removeFromSuperview() }
        func button(_ title: String, _ action: Selector) {
            buttons!.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        switch state {
        case .checking:
            messageLabel?.stringValue = "Checking for updates…"
            button("Close", #selector(dismiss(_:)))
        case let .available(release):
            messageLabel?.stringValue = "Capture \(release.version) (build \(release.build)) is available.\nInstalled: \(installed.version) (build \(installed.build))."
            button("Download", #selector(download(_:)))
            button("Release Notes", #selector(releaseNotes(_:)))
            button("Later", #selector(dismiss(_:)))
        case .current:
            messageLabel?.stringValue = "Capture is up to date.\nInstalled: \(installed.version) (build \(installed.build))."
            button("Close", #selector(dismiss(_:)))
        case let .failure(message):
            messageLabel?.stringValue = "Could not check for updates.\n\(message)"
            button("Try Again", #selector(checkForUpdates(_:)))
            button("Close", #selector(dismiss(_:)))
        }
        panel?.orderFront(nil)
    }
}
