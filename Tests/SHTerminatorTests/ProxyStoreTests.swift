import Foundation
import Testing
@testable import SHTerminator

@MainActor
@Suite struct ProxyStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shterminator-tests-\(UUID().uuidString)")
    var file: URL { dir.appendingPathComponent("proxies.json") }
    let shellDir = URL(fileURLWithPath: "/Apps/SH Terminator.app/Contents/Resources/shell")

    @Test func parsesURLsWithEncodedCredentials() throws {
        let (entry, password) = try #require(ProxyEntry.parse(" socks5://us%40er:p%3Ass%25w@203.0.113.7:8000 "))
        #expect(entry.host == "203.0.113.7")
        #expect(entry.port == 8000)
        #expect(entry.username == "us@er")
        #expect(password == "p:ss%w")
        #expect(!entry.remoteDNS)
        #expect(entry.url(password: password) == "socks5://us%40er:p%3Ass%25w@203.0.113.7:8000")
    }

    @Test func parsesIPv6AndBareAddresses() throws {
        let (v6, _) = try #require(ProxyEntry.parse("socks5h://[2001:db8::1]:1080"))
        #expect(v6.host == "2001:db8::1")
        #expect(v6.url(password: nil) == "socks5h://[2001:db8::1]:1080")
        let (bare, password) = try #require(ProxyEntry.parse("proxy.example:1080"))
        #expect(bare.remoteDNS)
        #expect(bare.username.isEmpty && password.isEmpty)
    }

    @Test func refusesWhatIsNotASOCKS5Proxy() {
        for text in ["http://203.0.113.7:8000", "socks5://203.0.113.7", "socks5://203.0.113.7:0", "socks5://h:1/path", "socks5://h:99999", ""] {
            #expect(ProxyEntry.parse(text) == nil, "\(text)")
        }
    }

    @Test func passwordsLiveInThePrivateFile() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProxyStore(fileURL: file)
        let entry = store.add(ProxyEntry(host: "203.0.113.7", port: 8000, username: "alice"), password: "s3cret-Pw")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(ProxyStore(fileURL: file).password(for: entry.id) == "s3cret-Pw")

        store.remove(id: entry.id)
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("s3cret-Pw"))
    }

    /// Files from when passwords were in the Keychain still load; those
    /// proxies just have no password until it is entered again.
    @Test func readsFilesWithoutPasswords() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID()
        try Data("""
            {"proxies":[{"id":"\(id.uuidString)","host":"203.0.113.7","port":8000,"username":"alice","remoteDNS":true}],
             "activeID":"\(id.uuidString)","tools":["curl"]}
            """.utf8).write(to: file)
        let store = ProxyStore(fileURL: file)
        #expect(store.active?.host == "203.0.113.7")
        #expect(store.password(for: id) == nil)
    }

    @Test func oneProxyInUseAtATime() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProxyStore(fileURL: file)
        let first = store.add(ProxyEntry(host: "203.0.113.7", port: 8000, username: ""), password: "")
        let second = store.add(ProxyEntry(host: "198.51.100.9", port: 1080, username: ""), password: "")
        #expect(store.activeID == first.id)
        store.setActive(second.id)
        #expect(store.activeID == second.id)
        store.setActive(nil)
        #expect(store.active == nil)
    }

    @Test func settingsSurviveARestart() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProxyStore(fileURL: file)
        #expect(store.tools == [.curl, .git, .brew])
        let entry = store.add(ProxyEntry(host: "203.0.113.7", port: 8000, username: "alice"), password: "pw")
        store.setTool(.ssh, enabled: true)
        store.setTool(.brew, enabled: false)

        let reloaded = ProxyStore(fileURL: file)
        #expect(reloaded.proxies == [entry])
        #expect(reloaded.activeID == entry.id)
        #expect(reloaded.tools == [.curl, .git, .ssh])
        #expect(reloaded.password(for: entry.id) == "pw")
    }

    @Test func editingWithoutAPasswordKeepsTheStoredOne() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProxyStore(fileURL: file)
        var entry = store.add(ProxyEntry(host: "203.0.113.7", port: 8000, username: "alice"), password: "pw")
        entry.port = 9000
        store.update(entry, password: nil)
        #expect(store.password(for: entry.id) == "pw")
        store.update(entry, password: "new")
        #expect(store.password(for: entry.id) == "new")
    }

    /// Every zsh pane gets the wrappers, proxy or not, so one set up later
    /// still reaches it; no URL or password in the environment.
    @Test func paneEnvironmentForZshOnly() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProxyStore(fileURL: file)
        let app = "/Apps/SH Terminator.app/Contents/MacOS/SHTerminator"
        let expected = [
            "ZDOTDIR=/Apps/SH Terminator.app/Contents/Resources/shell",
            "SHT_SHELL_DIR=/Apps/SH Terminator.app/Contents/Resources/shell",
            "SHT_APP=\(app)",
            "SHT_PROXY_CONFIG=\(file.path)",
        ]
        #expect(store.paneEnvironment(loginShell: "/bin/zsh", shellDirectory: shellDir, appExecutable: app) == expected)

        store.add(ProxyEntry(host: "203.0.113.7", port: 8000, username: "alice"), password: "p@ss")
        let env = store.paneEnvironment(loginShell: "/bin/zsh", shellDirectory: shellDir, appExecutable: app)
        #expect(env == expected)
        #expect(!env.joined().contains("p@ss") && !env.joined().contains("p%40ss"))

        // Not zsh or shell files missing: the shell starts as without this.
        #expect(store.paneEnvironment(loginShell: "/bin/bash", shellDirectory: shellDir, appExecutable: app).isEmpty)
        #expect(store.unavailableReason(loginShell: "/bin/bash", shellDirectory: shellDir) != nil)
        #expect(store.paneEnvironment(loginShell: "/bin/zsh", shellDirectory: nil, appExecutable: app).isEmpty)
        #expect(store.unavailableReason(loginShell: "/bin/zsh", shellDirectory: shellDir) == nil)
    }

    /// `--pane-proxy` answers only processes started under the running app.
    @Test func paneProxyQueryChecksItsAncestors() throws {
        let ownPath = try #require(PaneProxyQuery.executablePath(of: getpid()))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        #expect(PaneProxyQuery.hasAncestor(running: ownPath, above: child.processIdentifier))
        #expect(!PaneProxyQuery.hasAncestor(running: ownPath, above: getpid()))
        #expect(!PaneProxyQuery.hasAncestor(running: "/nonexistent/SHTerminator", above: child.processIdentifier))
    }

    @Test func shellFilesAreFoundInADebugBuild() throws {
        let dir = try #require(ProxyStore.shellDirectory)
        for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin", "sht-socks5"] {
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path), "\(name)")
        }
    }
}
