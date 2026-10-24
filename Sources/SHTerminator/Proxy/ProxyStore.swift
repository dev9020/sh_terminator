import Foundation

/// A program whose connections can go through the proxy.
enum ProxyTool: String, Codable, CaseIterable {
    case curl, git, brew, ssh

    /// Off until the user turns it on: ssh traffic is end-to-end encrypted
    /// anyway, and a proxy in front of it is what a first connection's
    /// host-key check must catch (see SECURITY.md §18).
    static let defaults: Set<ProxyTool> = [.curl, .git, .brew]
}

/// One SOCKS5 proxy. Its password is kept beside it, by `id`
/// (`ProxyStore.password(for:)`), so it never ends up in a listing.
struct ProxyEntry: Codable, Equatable {
    var id = UUID()
    var host: String
    var port: Int
    var username: String
    /// `socks5h`: curl and git hand server names to the proxy instead of
    /// looking them up with this Mac's DNS (ssh always does, see
    /// `sht-socks5`).
    var remoteDNS = true

    var scheme: String { remoteDNS ? "socks5h" : "socks5" }

    /// `host:port`, IPv6 addresses in brackets.
    var address: String {
        (host.contains(":") ? "[\(host)]" : host) + ":\(port)"
    }

    /// The proxy as a URL, with the password when given. User name and
    /// password are percent-encoded, so `@`, `:` or `%` in them survive.
    func url(password: String?) -> String {
        var credentials = ""
        if !username.isEmpty {
            credentials = Self.encode(username)
            if let password, !password.isEmpty { credentials += ":" + Self.encode(password) }
            credentials += "@"
        }
        return "\(scheme)://\(credentials)\(address)"
    }

    private static func encode(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// Reads `socks5://user:password@host:port` (or `socks5h://`, or no
    /// scheme at all). Returns nil for anything else.
    static func parse(_ text: String) -> (entry: ProxyEntry, password: String)? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "socks5h://" + text }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "socks5" || scheme == "socks5h",
              var host = components.host, !host.isEmpty,
              let port = components.port, (1...65535).contains(port),
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        let entry = ProxyEntry(host: host, port: port, username: components.user ?? "", remoteDNS: scheme == "socks5h")
        return (entry, components.password ?? "")
    }
}

/// The SOCKS5 proxies the user has added, which one is in use, and which
/// programs in the panes go through it.
///
/// The app itself still connects nowhere: a proxy only changes how the
/// panes' programs start. Every pane whose login shell is zsh reads
/// `Resources/shell` (via `ZDOTDIR`), which runs the user's own startup
/// files and then wraps curl, git, brew and ssh. Before each run a wrapper
/// checks whether `proxies.json` changed and, if it did, asks the app for
/// the proxy in use (`PaneProxyQuery`), so a change here reaches panes
/// that are already open (see `paneEnvironment` and SECURITY.md §18).
///
/// The list is kept at
/// `~/Library/Application Support/SHTerminator/proxies.json`, passwords
/// included, readable only by the current user (dir 0700, file 0600). Not
/// the Keychain, on purpose: with the app's ad-hoc signature changing on
/// every build, macOS would ask for Keychain access again and again.
@MainActor
final class ProxyStore {
    static let shared = ProxyStore()
    static let didChange = Notification.Name("ProxyStoreDidChange")

    private(set) var proxies: [ProxyEntry] = []
    /// The proxy the panes use; at most one, since a program can only go
    /// through one at a time.
    private(set) var activeID: UUID?
    private(set) var tools = ProxyTool.defaults

    private let fileURL: URL
    /// Only non-empty ones.
    private var passwords: [UUID: String] = [:]

    private struct File: Codable {
        var proxies: [ProxyEntry]
        var activeID: UUID?
        var tools: [ProxyTool]
        /// By proxy id. Missing in files written while passwords were in
        /// the Keychain: those proxies need their password entered again.
        var passwords: [String: String]?
    }

    init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SHTerminator", isDirectory: true)
        .appendingPathComponent("proxies.json")) {
        self.fileURL = fileURL
        load()
    }

    var active: ProxyEntry? {
        proxies.first { $0.id == activeID }
    }

    func password(for id: UUID) -> String? {
        passwords[id]
    }

    // MARK: - Editing

    /// A new proxy is put in use when none is.
    @discardableResult
    func add(_ entry: ProxyEntry, password: String) -> ProxyEntry {
        proxies.append(entry)
        storePassword(password, for: entry.id)
        if activeID == nil { activeID = entry.id }
        save()
        return entry
    }

    /// `password` nil keeps the stored one.
    func update(_ entry: ProxyEntry, password: String?) {
        guard let index = proxies.firstIndex(where: { $0.id == entry.id }) else { return }
        proxies[index] = entry
        if let password { storePassword(password, for: entry.id) }
        save()
    }

    func remove(id: UUID) {
        proxies.removeAll { $0.id == id }
        storePassword(nil, for: id)
        if activeID == id { activeID = nil }
        save()
    }

    /// Puts `id` in use (and every other proxy out of use); nil turns the
    /// proxy off.
    func setActive(_ id: UUID?) {
        guard id == nil || proxies.contains(where: { $0.id == id }), id != activeID else { return }
        activeID = id
        save()
    }

    func setTool(_ tool: ProxyTool, enabled: Bool) {
        guard tools.contains(tool) != enabled else { return }
        if enabled { tools.insert(tool) } else { tools.remove(tool) }
        save()
    }

    private func storePassword(_ password: String?, for id: UUID) {
        passwords[id] = (password?.isEmpty ?? true) ? nil : password
    }

    // MARK: - Panes

    /// Why the panes get no proxy even though one is chosen; nil when they do.
    func unavailableReason(loginShell: String, shellDirectory: URL? = ProxyStore.shellDirectory) -> String? {
        guard active != nil, !tools.isEmpty else { return nil }
        if (loginShell as NSString).lastPathComponent != "zsh" { return "needs zsh as the login shell" }
        if shellDirectory == nil { return "shell files missing from the app" }
        return nil
    }

    /// What a new pane's shell gets on top of `PaneSession.shellEnvironment`
    /// when it is zsh: `ZDOTDIR` pointing at `Resources/shell`, the app's
    /// binary to ask for the proxy and the file whose changes mean asking
    /// again. Whether or not a proxy is in use, so one set up later still
    /// reaches this pane. No proxy URL or password: those are fetched by
    /// the wrappers, only when needed (see `Resources/shell/.zshrc`).
    /// Other shells get nothing and start exactly as without this feature.
    func paneEnvironment(loginShell: String, shellDirectory: URL? = ProxyStore.shellDirectory,
                         appExecutable: String? = Bundle.main.executablePath) -> [String] {
        guard (loginShell as NSString).lastPathComponent == "zsh", let shellDirectory, let appExecutable else { return [] }
        return [
            "ZDOTDIR=\(shellDirectory.path)",
            "SHT_SHELL_DIR=\(shellDirectory.path)",
            "SHT_APP=\(appExecutable)",
            "SHT_PROXY_CONFIG=\(fileURL.path)",
        ]
    }

    /// `Contents/Resources/shell` in the app; in a debug build run from
    /// `.build`, the repo's `Resources/shell`.
    static let shellDirectory: URL? = {
        var candidates = [Bundle.main.resourceURL?.appendingPathComponent("shell", isDirectory: true)]
        #if DEBUG
        candidates.append(URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/shell", isDirectory: true))
        #endif
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(".zshrc").path)
                && FileManager.default.fileExists(atPath: $0.appendingPathComponent("sht-socks5").path)
        }
    }()

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            // Keep the unreadable file aside instead of overwriting it.
            let backup = fileURL.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return
        }
        proxies = file.proxies
        activeID = file.proxies.contains { $0.id == file.activeID } ? file.activeID : nil
        tools = Set(file.tools)
        for (key, password) in file.passwords ?? [:] {
            if let id = UUID(uuidString: key), proxies.contains(where: { $0.id == id }), !password.isEmpty {
                passwords[id] = password
            }
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let file = File(proxies: proxies, activeID: activeID, tools: ProxyTool.allCases.filter { tools.contains($0) },
                            passwords: Dictionary(uniqueKeysWithValues: passwords.map { ($0.key.uuidString, $0.value) }))
            try SecurityHardening.writePrivateFile(encoder.encode(file), to: fileURL)
        } catch {
            NSLog("sh_terminator: failed to save proxies: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: ProxyStore.didChange, object: self)
    }
}
