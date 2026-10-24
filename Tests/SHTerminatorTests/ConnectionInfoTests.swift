import Testing
import SystemConfiguration
@testable import SHTerminator

@Suite struct ConnectionInfoTests {
    @Test func interfaceKinds() {
        #expect(ConnectionInfo.kind(of: "en0") == .local)
        #expect(ConnectionInfo.kind(of: "utun4") == .vpn)
        #expect(ConnectionInfo.kind(of: "ipsec0") == .vpn)
        #expect(ConnectionInfo.kind(of: "ppp0") == .vpn)
        #expect(ConnectionInfo.kind(of: "lo0") == .ignored)
        #expect(ConnectionInfo.kind(of: "awdl0") == .ignored)
        #expect(ConnectionInfo.kind(of: "bridge100") == .ignored)
    }

    @Test func idleTunnelsWithOnlyLinkLocalAddressesAreNotAVPN() {
        let snapshot = ConnectionInfo.snapshot(
            addresses: [
                .init(interface: "en0", address: "fe80::1"),
                .init(interface: "en0", address: "192.168.1.23"),
                .init(interface: "utun0", address: "fe80::abcd"),
                .init(interface: "lo0", address: "127.0.0.1"),
            ],
            primaryInterface: "en0", names: ["en0": "Wi-Fi"], proxies: [:])
        #expect(snapshot.local == [.init(interface: "en0", name: "Wi-Fi", addresses: ["192.168.1.23"])])
        #expect(snapshot.vpn.isEmpty)
        #expect(snapshot.proxies.isEmpty)
    }

    @Test func activeTunnelPrimaryFirstIPv4First() {
        let snapshot = ConnectionInfo.snapshot(
            addresses: [
                .init(interface: "en1", address: "10.0.0.5"),
                .init(interface: "en0", address: "2001:db8::5"),
                .init(interface: "en0", address: "192.168.1.23"),
                .init(interface: "utun4", address: "10.8.0.2"),
            ],
            primaryInterface: "en0", names: [:], proxies: [:])
        #expect(snapshot.local.map(\.interface) == ["en0", "en1"])
        #expect(snapshot.local[0].addresses == ["192.168.1.23", "2001:db8::5"])
        #expect(snapshot.vpn == [.init(interface: "utun4", name: nil, addresses: ["10.8.0.2"])])
    }

    @Test func enabledProxiesOnly() {
        let proxies = ConnectionInfo.proxies(from: [
            kSCPropNetProxiesHTTPEnable as String: 1,
            kSCPropNetProxiesHTTPProxy as String: "127.0.0.1",
            kSCPropNetProxiesHTTPPort as String: 8080,
            kSCPropNetProxiesHTTPSEnable as String: 0,
            kSCPropNetProxiesHTTPSProxy as String: "ignored",
            kSCPropNetProxiesSOCKSEnable as String: 1,
            kSCPropNetProxiesSOCKSProxy as String: "proxy.local",
            kSCPropNetProxiesProxyAutoConfigEnable as String: 1,
            kSCPropNetProxiesProxyAutoConfigURLString as String: "http://wpad/proxy.pac",
        ])
        #expect(proxies == [
            .init(kind: "HTTP", endpoint: "127.0.0.1:8080"),
            .init(kind: "SOCKS", endpoint: "proxy.local"),
            .init(kind: "PAC", endpoint: "http://wpad/proxy.pac"),
        ])
    }

    @Test func readsThisMac() {
        let snapshot = ConnectionInfo.read(store: SCDynamicStoreCreate(nil, "SHTerminatorTests" as CFString, nil, nil))
        #expect(snapshot.local.allSatisfy { !$0.addresses.isEmpty })
    }
}
