import AppKit

/// "Connection" block under the notes: the Mac's own address, whether a VPN
/// tunnel is up (and its address in the tunnel) and the system proxy.
/// Follows `ConnectionMonitor`, so it changes as soon as the network does.
@MainActor
final class ConnectionPanel: NSObject {
    let view = NSView()

    private let localValue = ConnectionPanel.valueLabel()
    private let vpnValue = ConnectionPanel.valueLabel()
    private let proxyValue = ConnectionPanel.valueLabel()

    override init() {
        super.init()
        buildUI()
        update()
        NotificationCenter.default.addObserver(self, selector: #selector(monitorDidChange(_:)), name: ConnectionMonitor.didChange, object: nil)
    }

    @objc private func monitorDidChange(_ notification: Notification) {
        update()
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
        let title = Theme.sectionLabel("CONNECTION")
        let refresh = Theme.iconButton("arrow.clockwise", "Refresh", target: self, action: #selector(refresh(_:)))
        let header = NSStackView(views: [title, NSView(), refresh])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        let grid = NSGridView(views: [
            [Self.keyLabel("LAN"), localValue],
            [Self.keyLabel("VPN"), vpnValue],
            [Self.keyLabel("PROXY"), proxyValue],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .leading
        grid.rowAlignment = .firstBaseline

        // Said here so no one takes these for the address websites see.
        let note = NSTextField(wrappingLabelWithString: "Addresses on this Mac only. The public IP isn't looked up: the app makes no network requests.")
        note.font = Theme.mono(9)
        note.textColor = Theme.dimRed

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = Theme.faintRed.cgColor

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
        for label in [localValue, vpnValue, proxyValue, note] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    private static func keyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.mono(10, .bold)
        label.textColor = Theme.muted
        return label
    }

    private static func valueLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = Theme.mono(10)
        label.lineBreakMode = .byCharWrapping
        return label
    }
}
