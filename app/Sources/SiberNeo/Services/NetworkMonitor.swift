import AppKit
import CoreLocation
import CoreWLAN
import Network
import SystemConfiguration

enum WiFiSecurity: Equatable {
    case open, weak, wpa, wpa2, wpa3, enterprise, owe, unknown

    init(_ security: CWSecurity) {
        switch security.rawValue {
        case 0: self = .open
        case 1, 6: self = .weak
        case 2, 3: self = .wpa
        case 4, 5: self = .wpa2
        case 7, 8, 9, 10, 12: self = .enterprise
        case 11, 13: self = .wpa3
        case 14, 15: self = .owe
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .open: return tr("Tanpa enkripsi", "Unencrypted")
        case .weak: return tr("WEP (lemah)", "WEP (weak)")
        case .wpa: return "WPA"
        case .wpa2: return "WPA2"
        case .wpa3: return "WPA3"
        case .enterprise: return "Enterprise"
        case .owe: return "Enhanced Open"
        case .unknown: return tr("Tidak diketahui", "Unknown")
        }
    }

    var isInsecure: Bool {
        self == .open || self == .weak
    }
}

struct NetworkStatus: Equatable {
    var isConnected = false
    var onWiFi = false
    var onWired = false
    var ssid: String?
    var security: WiFiSecurity = .unknown
    var vpnActive = false

    var isRisky: Bool { onWiFi && security.isInsecure }
}

/// Monitors connection security: Wi-Fi encryption, VPN status, and network changes.
final class NetworkMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status = NetworkStatus()
    @Published private(set) var locationAuthorized = false

    var onChange: ((NetworkStatus, NetworkStatus) -> Void)?

    private let pathMonitor = NWPathMonitor()
    private let locationManager = CLLocationManager()
    private var lastPath: NWPath?
    private var timer: Timer?
    private var hasBaseline = false

    func start() {
        locationManager.delegate = self
        updateLocationAuthorization()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.lastPath = path
                self?.refresh()
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))

        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// macOS only exposes the Wi-Fi name (SSID) when Location permission is granted.
    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.updateLocationAuthorization()
            self.refresh()
        }
    }

    private func updateLocationAuthorization() {
        locationAuthorized = locationManager.authorizationStatus.rawValue >= 3
    }

    func refresh() {
        guard let path = lastPath else { return }

        var next = NetworkStatus()
        next.isConnected = path.status == .satisfied
        next.onWiFi = next.isConnected && path.availableInterfaces.contains { $0.type == .wifi }
        next.onWired = next.isConnected && path.availableInterfaces.contains { $0.type == .wiredEthernet }

        if next.onWiFi, let interface = CWWiFiClient.shared().interface() {
            next.ssid = interface.ssid()
            next.security = WiFiSecurity(interface.security())
        }
        next.vpnActive = Self.isVPNActive()

        let previous = status
        guard next != previous else {
            hasBaseline = true
            return
        }
        status = next
        if hasBaseline {
            onChange?(previous, next)
        }
        hasBaseline = true
    }

    /// VPN is detected from active network services that use a tunnel interface
    /// (IKEv2, WireGuard, OpenVPN, L2TP, and similar).
    static func isVPNActive() -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "SiberNeo" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String] else {
            return false
        }
        let prefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]
        for key in keys {
            guard let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let name = value["InterfaceName"] as? String else { continue }
            if prefixes.contains(where: { name.hasPrefix($0) }) {
                return true
            }
        }
        return false
    }
}
