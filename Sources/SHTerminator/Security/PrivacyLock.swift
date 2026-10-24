import AppKit
import LocalAuthentication

/// Covers every terminal window with an opaque lock screen, against someone
/// glancing at (or typing into) an unattended Mac — something
/// `sharingType = .none` can't help with.
///
/// - `.locked`: Lock Now (⌃⌘L), no input in this app for
///   `AppSettings.autoLockMinutes`, or (with `AppSettings.lockOnSleep`) the
///   Mac or its screens going to sleep, the screen being locked, or a switch
///   to another user. Unlocking needs Touch ID or the macOS account password.
/// - `.covered`: `AppSettings.hideWhenInactive` and another app is in front.
///   Coming back to this app uncovers the windows, no authentication.
///
/// While engaged, windows take their panes and sidebar out of the view
/// hierarchy entirely (see `PaneWindowController.privacyLockDidChange`), so
/// no key, click or menu shortcut can reach a pane; the shells keep running.
@MainActor
final class PrivacyLock {
    static let shared = PrivacyLock()
    static let didChange = Notification.Name("PrivacyLockDidChange")

    enum State {
        case unlocked
        case covered
        case locked
    }

    private(set) var state: State = .unlocked
    var isEngaged: Bool { state != .unlocked }

    private var lastActivity = Date()
    private var activityMonitor: Any?
    private var idleTimer: Timer?
    private var sleepObservers: [NSObjectProtocol] = []
    private var isAuthenticating = false

    private init() {}

    func start() {
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockIfIdle() }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let triggers: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
        ]
        sleepObservers = triggers.map { center, name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if AppSettings.lockOnSleep { self?.lock() }
                }
            }
        }
    }

    func lock() {
        set(.locked)
    }

    func appDidResignActive() {
        if AppSettings.hideWhenInactive && state == .unlocked {
            set(.covered)
        }
    }

    func appDidBecomeActive() {
        if state == .covered {
            set(.unlocked)
        }
    }

    /// Asks for Touch ID / the account password, then unlocks.
    func unlock() {
        switch state {
        case .unlocked:
            return
        case .covered:
            set(.unlocked)
            return
        case .locked:
            break
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let context = LAContext()
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock your terminal windows")
                if ok { set(.unlocked) }
            } catch {
                // Cancelled or failed: stay locked.
            }
        }
    }

    private func lockIfIdle() {
        let minutes = AppSettings.autoLockMinutes
        guard minutes > 0, state != .locked else { return }
        if Date().timeIntervalSince(lastActivity) >= TimeInterval(minutes * 60) {
            lock()
        }
    }

    private func set(_ newState: State) {
        guard newState != state else { return }
        state = newState
        if newState == .unlocked { lastActivity = Date() }
        NotificationCenter.default.post(name: PrivacyLock.didChange, object: self)
    }
}
