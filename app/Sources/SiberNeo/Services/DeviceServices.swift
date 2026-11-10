import Foundation
import IOBluetooth
import IOKit.ps

/// Battery status based on IOKit notifications (no polling).
final class PowerService: ObservableObject {
    @Published private(set) var percent: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var onAC = false

    var onPluggedIn: ((Int?) -> Void)?
    var onLowBattery: ((Int) -> Void)?

    private var source: CFRunLoopSource?

    init() {
        refresh(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let unmanaged = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            service.refresh(notify: true)
        }, context) {
            let loopSource = unmanaged.takeRetainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .defaultMode)
            source = loopSource
        }
    }

    var symbol: String {
        if isCharging || onAC { return "battery.100.bolt" }
        let value = percent ?? 0
        if value >= 88 { return "battery.100" }
        if value >= 63 { return "battery.75" }
        if value >= 38 { return "battery.50" }
        if value >= 13 { return "battery.25" }
        return "battery.0"
    }

    private func refresh(notify: Bool) {
        let wasOnAC = onAC
        let previousPercent = percent
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description["Type"] as? String) == "InternalBattery" else { continue }
            let current = description["Current Capacity"] as? Int ?? 0
            let capacity = description["Max Capacity"] as? Int ?? 100
            percent = capacity > 0 ? Int((Double(current) / Double(capacity) * 100).rounded()) : current
            isCharging = description["Is Charging"] as? Bool ?? false
            onAC = (description["Power Source State"] as? String) == "AC Power"
        }

        if notify, onAC, !wasOnAC {
            onPluggedIn?(percent)
        }
        if notify, !onAC, let current = percent, current <= 20, (previousPercent ?? 100) > 20 {
            onLowBattery?(current)
        }
    }
}

/// Detects Bluetooth audio devices (AirPods, headphones) connecting or disconnecting.
final class BluetoothWatcher: NSObject {
    var onEvent: ((String, Bool) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    private var isWarmingUp: Bool {
        Date().timeIntervalSince(startedAt) < 3
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.deviceClassMajor == 0x04 else { return }
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        guard !isWarmingUp else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(device.name ?? tr("Perangkat audio", "Audio device"), true)
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(device.name ?? tr("Perangkat audio", "Audio device"), false)
        }
    }
}
