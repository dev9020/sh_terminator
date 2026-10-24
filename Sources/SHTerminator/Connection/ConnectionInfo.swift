import AppKit
import SystemConfiguration

/// What the "Connection" panel shows: the Mac's own addresses, any VPN
/// tunnel that is up and the system proxy. Everything comes from local
/// state (`getifaddrs` and the SystemConfiguration dynamic store); nothing
/// is sent over the network, so the public address the provider or VPN
/// gives the Mac is not known here.
struct ConnectionSnapshot: Equatable {
    struct Link: Equatable {
        let interface: String
        /// "Wi-Fi", "Ethernet", a VPN's service name, when the system has one.
        let name: String?
        let addresses: [String]
    }

    struct Proxy: Equatable {
        /// "HTTP", "HTTPS", "SOCKS", "PAC" or "Auto".
        let kind: String
        /// host:port, the PAC URL, or empty for auto-discovery.
        let endpoint: String
    }

    var local: [Link] = []
    var vpn: [Link] = []
    var proxies: [Proxy] = []
}

/// One address of one interface, as `getifaddrs` reports it.
struct InterfaceAddress: Equatable {
    let interface: String
    let address: String
}

enum ConnectionInfo {
    enum Kind { case local, vpn, ignored }

    /// Interfaces VPN clients create: utun (WireGuard, OpenVPN Connect,
    /// Network Extension VPNs), ipsec (built-in IKEv2/IPSec), ppp (L2TP),
    /// tun/tap (older OpenVPN drivers).
    private static let vpnPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]
    /// Loopback, AirDrop/Wi-Fi Aware, tunnels for IPv6 transition, Apple's
    /// internal links and the bridges for Internet Sharing and VMs: none is
    /// how the Mac reaches the Internet.
    private static let ignoredPrefixes = ["lo", "awdl", "llw", "gif", "stf", "anpi", "ap", "bridge", "vmenet", "vmnet", "XHC"]

    static func kind(of interface: String) -> Kind {
        if vpnPrefixes.contains(where: interface.hasPrefix) { return .vpn }
        if ignoredPrefixes.contains(where: interface.hasPrefix) { return .ignored }
        return .local
    }

    /// Link-local addresses (169.254/16, fe80::/10) only reach the same
    /// cable or Wi-Fi. Every idle utun (iCloud Private Relay, Continuity)
    /// has one, so they would make a VPN look up when it isn't.
    static func isLinkLocal(_ address: String) -> Bool {
        let lower = address.lowercased()
        return lower.hasPrefix("169.254.") || lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb")
    }

    /// Groups addresses by interface; the primary interface (the one
    /// carrying the default route) goes first, the rest keep their order.
    static func snapshot(addresses: [InterfaceAddress], primaryInterface: String?, names: [String: String], proxies: [String: Any]) -> ConnectionSnapshot {
        var order: [String] = []
        var byInterface: [String: [String]] = [:]
        for item in addresses where kind(of: item.interface) != .ignored && !isLinkLocal(item.address) {
            if byInterface[item.interface] == nil { order.append(item.interface) }
            byInterface[item.interface, default: []].append(item.address)
        }
        if let primaryInterface, let index = order.firstIndex(of: primaryInterface) {
            order.insert(order.remove(at: index), at: 0)
        }

        var snapshot = ConnectionSnapshot()
        for interface in order {
            // IPv4 first: it is what people recognise and compare.
            let sorted = byInterface[interface, default: []].sorted { !$0.contains(":") && $1.contains(":") }
            let link = ConnectionSnapshot.Link(interface: interface, name: names[interface], addresses: sorted)
            if kind(of: interface) == .vpn { snapshot.vpn.append(link) } else { snapshot.local.append(link) }
        }
        snapshot.proxies = self.proxies(from: proxies)
        return snapshot
    }

    /// The enabled proxies in a `SCDynamicStoreCopyProxies` dictionary.
    static func proxies(from settings: [String: Any]) -> [ConnectionSnapshot.Proxy] {
        func enabled(_ key: CFString) -> Bool { (settings[key as String] as? NSNumber)?.boolValue ?? false }
        var result: [ConnectionSnapshot.Proxy] = []
        let servers: [(String, CFString, CFString, CFString)] = [
            ("HTTP", kSCPropNetProxiesHTTPEnable, kSCPropNetProxiesHTTPProxy, kSCPropNetProxiesHTTPPort),
            ("HTTPS", kSCPropNetProxiesHTTPSEnable, kSCPropNetProxiesHTTPSProxy, kSCPropNetProxiesHTTPSPort),
            ("SOCKS", kSCPropNetProxiesSOCKSEnable, kSCPropNetProxiesSOCKSProxy, kSCPropNetProxiesSOCKSPort),
        ]
        for (kind, enable, host, port) in servers where enabled(enable) {
            guard let host = settings[host as String] as? String, !host.isEmpty else { continue }
            let port = (settings[port as String] as? NSNumber).map { ":\($0.intValue)" } ?? ""
            result.append(.init(kind: kind, endpoint: host + port))
        }
        if enabled(kSCPropNetProxiesProxyAutoConfigEnable) {
            result.append(.init(kind: "PAC", endpoint: settings[kSCPropNetProxiesProxyAutoConfigURLString as String] as? String ?? ""))
        }
        if enabled(kSCPropNetProxiesProxyAutoDiscoveryEnable) {
            result.append(.init(kind: "Auto", endpoint: ""))
        }
        return result
    }

    // MARK: - Reading the system state

    /// The current state, read from the system.
    static func read(store: SCDynamicStore?) -> ConnectionSnapshot {
        let primary = (store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) } as? [String: Any])?[kSCDynamicStorePropNetPrimaryInterface as String] as? String
        let proxies = SCDynamicStoreCopyProxies(store) as? [String: Any] ?? [:]
        return snapshot(addresses: interfaceAddresses(), primaryInterface: primary, names: interfaceNames(store: store), proxies: proxies)
    }

    /// IPv4 and IPv6 addresses of the interfaces that are up and running.
    private static func interfaceAddresses() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var result: [InterfaceAddress] = []
        var cursor = head
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, let sockaddr = entry.ifa_addr else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            switch Int32(sockaddr.pointee.sa_family) {
            case AF_INET:
                var address = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { continue }
            case AF_INET6:
                var address = sockaddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { continue }
            default:
                continue
            }
            let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            result.append(InterfaceAddress(interface: String(cString: entry.ifa_name), address: text))
        }
        return result
    }

    /// Human names for interfaces: the network service's name from System
    /// Settings ("Wi-Fi", "Office VPN"), else the hardware's name.
    private static func interfaceNames(store: SCDynamicStore?) -> [String: String] {
        var names: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            if let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                names[bsdName] = name
            }
        }
        guard let store else { return names }
        for family in ["IPv4", "IPv6"] {
            let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/\(family)" as CFString) as? [String] ?? []
            for key in keys {
                guard let state = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                      let interface = state[kSCPropInterfaceName as String] as? String else { continue }
                let service = key.split(separator: "/")[3]
                let setup = SCDynamicStoreCopyValue(store, "Setup:/Network/Service/\(service)" as CFString) as? [String: Any]
                if let name = setup?[kSCPropUserDefinedName as String] as? String, !name.isEmpty {
                    names[interface] = name
                }
            }
        }
        return names
    }
}

/// Keeps the current `ConnectionSnapshot` and posts `didChange` when it
/// changes. The system tells it about every change to addresses, routes and
/// proxies; a slow timer covers anything that slips past those notices.
@MainActor
final class ConnectionMonitor {
    static let shared = ConnectionMonitor()
    static let didChange = Notification.Name("ConnectionMonitor.didChange")

    private(set) var snapshot = ConnectionSnapshot()
    private var store: SCDynamicStore?
    private var pendingRefresh = false

    private init() {
        var context = SCDynamicStoreContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        // The source is on the main run loop, so the callback runs there.
        store = SCDynamicStoreCreate(nil, "SHTerminator" as CFString, { _, _, _ in
            MainActor.assumeIsolated { ConnectionMonitor.shared.scheduleRefresh() }
        }, &context)
        if let store {
            let keys = ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6", "State:/Network/Global/Proxies"]
            let patterns = [
                "State:/Network/Interface/[^/]+/IPv4", "State:/Network/Interface/[^/]+/IPv6", "State:/Network/Interface/[^/]+/Link",
                "State:/Network/Service/[^/]+/IPv4", "State:/Network/Service/[^/]+/IPv6",
            ]
            SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray)
            if let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Bringing up a VPN changes a dozen keys within a moment; read once
    /// they have settled.
    private func scheduleRefresh() {
        guard !pendingRefresh else { return }
        pendingRefresh = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                self.pendingRefresh = false
                self.refresh()
            }
        }
    }

    func refresh() {
        let current = ConnectionInfo.read(store: store)
        guard current != snapshot else { return }
        snapshot = current
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
