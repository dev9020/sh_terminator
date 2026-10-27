import AppKit

/// "Connection" block under the notes: the Mac's own address, whether a VPN
/// tunnel is up (and its address in the tunnel), the system proxy and the
/// app's own proxy for the panes (`ProxyStore`). Follows `ConnectionMonitor`,
/// so it changes as soon as the network does.
@MainActor
final class ConnectionPanel: NSObject {
    let view = NSView()

    private let localValue = ConnectionPanel.valueLabel()
    private let vpnValue = ConnectionPanel.valueLabel()
    private let proxyValue = ConnectionPanel.valueLabel()
    private let panesValue = ConnectionPanel.valueLabel()
    private let sectionTitle = Theme.sectionLabel("CONNECTION")
    private let note = NSTextField(wrappingLabelWithString: "Addresses on this Mac only. The public IP isn't looked up: the app makes no network requests.")
    private let separator = NSView()
    private let keyLabels = ["LAN", "VPN", "SYS PROXY", "PANE PROXY"].map { ConnectionPanel.keyLabel($0) }
    private var refreshButton: NSButton!
    private var proxyButton: NSButton!

    override init() {
        super.init()
        buildUI()
        update()
        NotificationCenter.default.addObserver(self, selector: #selector(monitorDidChange(_:)), name: ConnectionMonitor.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(monitorDidChange(_:)), name: ProxyStore.didChange, object: nil)
    }

    @objc private func monitorDidChange(_ notification: Notification) {
        update()
    }

    @objc private func showProxy(_ sender: Any?) {
        AppDelegate.shared.showProxy(sender)
    }

    @objc private func refresh(_ sender: Any?) {
        ConnectionMonitor.shared.refresh()
    }

    private func update() {
        let snapshot = ConnectionMonitor.shared.snapshot
        set(localValue, snapshot.local.isEmpty ? nil : snapshot.local.map { Self.describe($0) }.joined(separator: "\n"), off: "no network")
        set(vpnValue, snapshot.vpn.isEmpty ? nil : snapshot.vpn.map { Self.describe($0) }.joined(separator: "\n"), off: "off")
        let proxies = snapshot.proxies.map { $0.endpoint.isEmpty ? $0.kind : "\($0.kind) \($0.endpoint)" }
        set(proxyValue, proxies.isEmpty ? nil : proxies.joined(separator: "\n"), off: "off")
        set(panesValue, Self.describePaneProxy(), off: ProxyStore.shared.unavailableReason(loginShell: PaneSession.loginShellPath()).map { "off: \($0)" } ?? "off")
    }

    /// The app's own proxy for the panes (`ProxyStore`), nil when off.
    private static func describePaneProxy() -> String? {
        let store = ProxyStore.shared
        guard let active = store.active, !store.tools.isEmpty,
              store.unavailableReason(loginShell: PaneSession.loginShellPath()) == nil else { return nil }
        let tools = ProxyTool.allCases.filter { store.tools.contains($0) }.map(\.rawValue).joined(separator: " ")
        return "\(active.scheme) \(active.address)\n\(tools)"
    }

    private static func describe(_ link: ConnectionSnapshot.Link) -> String {
        let title = link.name.map { "\($0) (\(link.interface))" } ?? link.interface
        return ([title] + link.addresses).joined(separator: "\n")
    }

    /// Active values stand out in `hot`; "off" stays `muted`.
    private func set(_ label: NSTextField, _ text: String?, off: String) {
        label.stringValue = text ?? off
        label.textColor = text == nil ? Theme.muted : Theme.hot
    }

    // MARK: - UI

    private func buildUI() {
        refreshButton = Theme.iconButton("arrow.clockwise", "Refresh", target: self, action: #selector(refresh(_:)))
        // Same panel as sh_terminator → Proxy for Panes…
        proxyButton = Theme.iconButton("network", "Proxy for Panes", target: self, action: #selector(showProxy(_:)))
        proxyButton.toolTip = "Proxy for Panes…"
        let header = NSStackView(views: [sectionTitle, NSView(), proxyButton, refreshButton])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        let grid = NSGridView(views: zip(keyLabels, [localValue, vpnValue, proxyValue, panesValue]).map { [$0, $1] as [NSView] })
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .leading
        grid.rowAlignment = .firstBaseline

        // Said here so no one takes these for the address websites see.
        note.font = Theme.mono(9)

        separator.wantsLayer = true

        applyTheme()

        for subview in [separator, header, grid, note] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            header.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
            grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 8),
            note.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            note.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            note.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        for label in [localValue, vpnValue, proxyValue, panesValue, note] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    func applyTheme() {
        sectionTitle.textColor = Theme.red
        refreshButton.contentTintColor = Theme.red
        proxyButton.contentTintColor = Theme.red
        note.textColor = Theme.dimRed
        separator.layer?.backgroundColor = Theme.faintRed.cgColor
        for label in keyLabels { label.textColor = Theme.muted }
        update()
    }

    private static func keyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.mono(10, .bold)
        return label
    }

    private static func valueLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = Theme.mono(10)
        label.lineBreakMode = .byCharWrapping
        return label
    }
}
