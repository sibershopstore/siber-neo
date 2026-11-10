import SwiftUI

struct SecurityTabView: View {
    @EnvironmentObject var privacy: PrivacyMonitor
    @EnvironmentObject var network: NetworkMonitor

    var body: some View {
        let status = network.status
        let warning = status.isRisky

        HStack(spacing: 18) {
            VStack(spacing: 8) {
                MascotView(size: 52, interactive: true)
                    .frame(height: 56)
                Text(warning ? tr("Perlu perhatian", "Needs attention") : tr("Kondisi normal", "All clear"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(warning ? Theme.red : Color.white)
                Text(warning ? tr("Wi-Fi yang terhubung tidak terenkripsi.", "The connected Wi-Fi is not encrypted.") : tr("Kamera, mikrofon, dan jaringan terpantau.", "Camera, microphone, and network are monitored."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PaletteSwatches()
                    .padding(.top, 4)
                AccessoryPicker()
            }
            .frame(width: 150)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    SecurityCard(
                        icon: privacy.cameraActive ? "video.fill" : "video",
                        title: tr("Kamera", "Camera"),
                        value: privacy.cameraActive ? tr("Sedang digunakan", "In use") : tr("Tidak digunakan", "Not in use"),
                        tint: privacy.cameraActive ? Theme.red : Theme.green
                    )
                    SecurityCard(
                        icon: privacy.micActive ? "mic.fill" : "mic",
                        title: tr("Mikrofon", "Microphone"),
                        value: micDescription,
                        tint: privacy.micActive ? Theme.amber : Theme.green
                    )
                }
                HStack(spacing: 8) {
                    SecurityCard(
                        icon: networkIcon(status),
                        title: tr("Jaringan", "Network"),
                        value: networkDescription(status),
                        tint: !status.isConnected ? Theme.secondary : (warning ? Theme.red : Theme.green)
                    )
                    SecurityCard(
                        icon: status.vpnActive ? "lock.shield.fill" : "lock.open",
                        title: "VPN",
                        value: status.vpnActive ? tr("Aktif", "On") : tr("Tidak aktif", "Off"),
                        tint: status.vpnActive ? Theme.green : Theme.secondary
                    )
                }
                if status.onWiFi, status.ssid == nil, !network.locationAuthorized {
                    HStack {
                        Text(tr("Nama Wi-Fi memerlukan izin Lokasi dari macOS.", "macOS requires Location access to show the Wi-Fi name."))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiary)
                        Spacer()
                        Button(tr("Izinkan", "Allow")) { network.requestLocationAccess() }
                            .buttonStyle(ChipStyle())
                    }
                }
            }
        }
    }

    private var micDescription: String {
        guard privacy.micActive else { return tr("Tidak digunakan", "Not in use") }
        return privacy.micApps.isEmpty ? tr("Sedang digunakan", "In use") : privacy.micApps.joined(separator: ", ")
    }

    private func networkIcon(_ status: NetworkStatus) -> String {
        if !status.isConnected { return "wifi.slash" }
        if status.isRisky { return "wifi.exclamationmark" }
        if status.onWiFi { return "wifi" }
        return "network"
    }

    private func networkDescription(_ status: NetworkStatus) -> String {
        if !status.isConnected { return tr("Tidak terhubung", "Not connected") }
        if status.onWiFi {
            let name = status.ssid ?? "Wi-Fi"
            return "\(name) · \(status.security.title)"
        }
        if status.onWired { return "Ethernet" }
        return tr("Terhubung", "Connected")
    }
}

struct SecurityCard: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
    }
}
