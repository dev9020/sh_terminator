import Darwin
import Foundation

/// `SHTerminator --pane-proxy`: how a pane's zsh learns the proxy in use
/// (see `Resources/shell/.zshrc`), so a proxy added or changed in the app
/// reaches panes that are already open, on their next wrapped command.
///
/// Prints two lines, the programs to wrap and the proxy URL with its
/// password, or nothing when no proxy is in use. Only a process started
/// from one of this app's panes gets an answer: one of its ancestors must
/// be the running app (the same executable, not this process).
@MainActor
enum PaneProxyQuery {
    static let argument = "--pane-proxy"

    /// Exit status for the process.
    static func run() -> Int32 {
        guard isStartedFromAPane() else {
            FileHandle.standardError.write(Data("sh_terminator: --pane-proxy only answers the app's own panes\n".utf8))
            return 1
        }
        let store = ProxyStore.shared
        guard let active = store.active, !store.tools.isEmpty else { return 0 }
        let tools = ProxyTool.allCases.filter { store.tools.contains($0) }.map(\.rawValue).joined(separator: " ")
        FileHandle.standardOutput.write(Data("\(tools)\n\(active.url(password: store.password(for: active.id)))\n".utf8))
        return 0
    }

    private static func isStartedFromAPane() -> Bool {
        guard let ownPath = executablePath(of: getpid()) else { return false }
        return hasAncestor(running: ownPath, above: getpid())
    }

    /// Whether a process above `pid` (not `pid` itself) runs `path`.
    static func hasAncestor(running path: String, above pid: pid_t) -> Bool {
        guard var pid = parentPID(of: pid) else { return false }
        // A pane's shell is the app's child; the wrapper and this query a
        // few levels below. Cap the walk in case of a cycle.
        for _ in 0..<64 where pid > 1 {
            if executablePath(of: pid) == path { return true }
            guard let parent = parentPID(of: pid), parent != pid else { return false }
            pid = parent
        }
        return false
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }
}
