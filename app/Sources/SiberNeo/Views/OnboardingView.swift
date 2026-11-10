import AppKit
import CoreBluetooth
import ServiceManagement
import SwiftUI
import UserNotifications

/// State and actions for onboarding. Permissions are requested one at a time with the user's consent.
/// All state is changed on the main thread only.
final class OnboardingModel: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case pending, requested, granted, denied
    }

    static let pageCount = 4

    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingDone") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingDone") }
    }

    @Published var page = 0
    @Published var notifications: Status = .pending
    @Published var bluetooth: Status = .pending
    @Published var folder: Status = .pending
    @Published var automation: Status = .pending
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var mascotName = UserProfile.mascotName {
        didSet { UserProfile.mascotName = mascotName }
    }
    @Published var birthdaySaved = UserProfile.birthday != nil
    @Published var birthdayDate: Date = {
        let calendar = Calendar.current
        if let birthday = UserProfile.birthday,
           let date = calendar.date(from: DateComponents(year: 2000, month: birthday.month, day: birthday.day)) {
            return date
        }
        return calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()
    }() {
        didSet {
            let parts = Calendar.current.dateComponents([.month, .day], from: birthdayDate)
            if let month = parts.month, let day = parts.day {
                UserProfile.birthday = (month, day)
                birthdaySaved = true
            }
        }
    }

    /// Called after each permission request so the onboarding window returns to the front.
    var afterRequest: (() -> Void)?
    var requestBluetoothAction: (() -> Void)?
    var requestFolderAction: (() -> Void)?
    var requestAutomationAction: (() -> Void)?

    func refresh() {
        refreshNotifications()
        refreshBluetooth()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func refreshNotifications() {
        guard Notifier.isAvailable else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: Status
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = .granted
            case .denied: status = .denied
            default: status = .pending
            }
            DispatchQueue.main.async {
                self.notifications = status
            }
        }
    }

    func requestNotifications() {
        guard Notifier.isAvailable else {
            notifications = .requested
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.notifications = granted ? .granted : .denied
                self.afterRequest?()
            }
        }
    }

    func refreshBluetooth() {
        switch CBManager.authorization {
        case .allowedAlways: bluetooth = .granted
        case .denied, .restricted: bluetooth = .denied
        default: break
        }
    }

    func requestBluetooth() {
        bluetooth = .requested
        requestBluetoothAction?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshBluetooth()
            self?.afterRequest?()
        }
    }

    func requestFolder() {
        folder = .requested
        requestFolderAction?()
    }

    func requestAutomation() {
        automation = .requested
        requestAutomationAction?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.afterRequest?()
        }
    }

    /// For permissions managed by other services (Calendar, Location).
    func notifyAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.afterRequest?()
        }
    }

    func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Siber Neo: \(error.localizedDescription)")
        }
        loginEnabled = service.status == .enabled
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var prayer: PrayerService
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case 0: welcome
                case 1: tour
                case 2: permissions
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 38)
            .id(model.page)
            .transition(.opacity)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(width: 600, height: 480)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.01, green: 0.02, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: model.page)
        .onAppear { model.refresh() }
    }

    // MARK: - Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            MascotView(size: 120, interactive: true)
                .frame(height: 120)
            Text(tr("Halo, saya \(UserProfile.mascotName)", "Hi, I'm \(UserProfile.mascotName)"))
                .font(.system(size: 28, weight: .bold))
            Text(tr(
                "Mulai sekarang, notch di layar Mac menjadi pusat kecil untuk musik, agenda, fokus, dan keamanan. Saya akan memandu pengaturannya, cukup satu menit.",
                "From now on, the notch on your Mac becomes a small hub for music, events, focus, and security. Setup takes about a minute, and I'll guide you."
            ))
            .font(.system(size: 14))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var tour: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Cara memakai Siber Neo", "How to use Siber Neo"))
                .font(.system(size: 22, weight: .bold))
            VStack(alignment: .leading, spacing: 14) {
                TourRow(
                    icon: "cursorarrow.motionlines",
                    title: tr("Arahkan kursor ke notch", "Hover over the notch"),
                    detail: tr("Panel terbuka otomatis dan menutup saat kursor menjauh.", "The panel opens on its own and closes when you move away.")
                )
                TourRow(
                    icon: "square.grid.2x2",
                    title: tr("Berpindah tab", "Switch tabs"),
                    detail: tr("Ikon di kiri atas membuka Musik, Fokus, To-do, Agenda, Harian, Shelf, Sholat, dan Keamanan.", "Icons at the top left open Music, Focus, To-do, Agenda, Daily, Shelf, Prayer, and Security.")
                )
                TourRow(
                    icon: "tray.and.arrow.down",
                    title: tr("Tarik file ke notch", "Drag files to the notch"),
                    detail: tr("File tersimpan di Shelf, siap ditarik ke chat atau email.", "Files wait in the Shelf, ready to drag into a chat or email.")
                )
                TourRow(
                    icon: "eye.slash",
                    title: tr("Mode presentasi", "Presentation mode"),
                    detail: tr("Klik ikon mata saat berbagi layar agar notifikasi tidak muncul.", "Click the eye icon while sharing your screen to keep notifications hidden.")
                )
                TourRow(
                    icon: "shield.lefthalf.filled",
                    title: tr("Menu di menu bar", "Menu bar menu"),
                    detail: tr("Ikon perisai berisi pengaturan seperti kota, bahasa, dan warna \(UserProfile.mascotName).", "The shield icon holds settings like city, language, and \(UserProfile.mascotName)'s color.")
                )
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Izin yang diperlukan", "Permissions"))
                .font(.system(size: 22, weight: .bold))
            Text(tr(
                "Setiap izin hanya dipakai untuk fitur terkait, dan semua data tetap di Mac.",
                "Each permission is used only for its feature, and all data stays on your Mac."
            ))
            .font(.system(size: 12))
            .foregroundStyle(Theme.tertiary)
            .padding(.bottom, 4)

            PermissionRow(
                icon: "bell.badge.fill",
                title: tr("Notifikasi", "Notifications"),
                detail: tr("Pengingat tugas, agenda, sholat, dan minum air.", "Reminders for tasks, events, prayer, and water."),
                status: model.notifications
            ) { model.requestNotifications() }

            PermissionRow(
                icon: "music.note",
                title: tr("Musik dan YouTube", "Music and YouTube"),
                detail: tr("macOS akan bertanya saat Spotify, Music, atau Chrome terdeteksi.", "macOS will ask when Spotify, Music, or Chrome is detected."),
                status: model.automation
            ) { model.requestAutomation() }

            PermissionRow(
                icon: "camera.viewfinder",
                title: tr("Folder screenshot", "Screenshot folder"),
                detail: tr("Agar screenshot baru otomatis masuk Shelf.", "So new screenshots go straight to the Shelf."),
                status: model.folder
            ) { model.requestFolder() }

            PermissionRow(
                icon: "headphones",
                title: "Bluetooth",
                detail: tr("Status AirPods dan headphone saat terhubung.", "Shows when AirPods and headphones connect."),
                status: model.bluetooth
            ) { model.requestBluetooth() }

            PermissionRow(
                icon: "calendar",
                title: tr("Kalender", "Calendar"),
                detail: tr("Agenda berikutnya dan tombol gabung rapat.", "Your next event and a join-meeting button."),
                status: calendarStatus
            ) {
                calendar.requestAccess()
                model.notifyAfterDelay()
            }

            PermissionRow(
                icon: "location.fill",
                title: tr("Lokasi (opsional)", "Location (optional)"),
                detail: tr("Hanya untuk menampilkan nama Wi-Fi di tab Keamanan.", "Only used to show the Wi-Fi name in Security."),
                status: network.locationAuthorized ? .granted : .pending
            ) {
                network.requestLocationAccess()
                model.notifyAfterDelay()
            }
        }
    }

    private var finish: some View {
        VStack(spacing: 16) {
            Text(tr("Sentuhan terakhir", "Final touches"))
                .font(.system(size: 22, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 28) {
                VStack(spacing: 12) {
                    MascotView(size: 76, interactive: true)
                        .frame(height: 76)
                    PaletteSwatches()
                    Text(tr("Pilih warna \(UserProfile.mascotName)", "Pick \(UserProfile.mascotName)'s color"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(width: 170)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Kota untuk jadwal sholat dan cuaca", "City for prayer times and weather"))
                            .font(.system(size: 12, weight: .semibold))
                        Menu {
                            ForEach(City.all, id: \.name) { city in
                                Button(city.name) { prayer.city = city }
                            }
                        } label: {
                            Text(prayer.city.name)
                                .font(.system(size: 12))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Nama maskot", "Mascot name"))
                                .font(.system(size: 12, weight: .semibold))
                            TextField(UserProfile.defaultMascotName, text: $model.mascotName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(width: 110)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Ulang tahun (opsional)", "Birthday (optional)"))
                                .font(.system(size: 12, weight: .semibold))
                            DatePicker("", selection: $model.birthdayDate, displayedComponents: [.date])
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .environment(\.locale, Lang.locale)
                                .frame(width: 120)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Buka otomatis", "Launch automatically"))
                            .font(.system(size: 12, weight: .semibold))
                        Button(model.loginEnabled
                               ? tr("Aktif saat Mac dinyalakan", "On at login")
                               : tr("Aktifkan saat Mac dinyalakan", "Turn on at login")) {
                            model.toggleLogin()
                        }
                        .buttonStyle(ChipStyle(selected: model.loginEnabled))
                    }

                    Text(tr(
                        "Semua pengaturan bisa diubah kapan saja lewat ikon perisai di menu bar.",
                        "You can change everything later from the shield icon in the menu bar."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let isLast = model.page >= OnboardingModel.pageCount - 1
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<OnboardingModel.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == model.page ? Theme.red : Color.white.opacity(0.18))
                        .frame(width: index == model.page ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if model.page > 0 {
                Button(tr("Kembali", "Back")) { model.page -= 1 }
                    .buttonStyle(PillButtonStyle())
            }
            Button(isLast ? tr("Mulai pakai Siber Neo", "Start using Siber Neo") : tr("Lanjut", "Next")) {
                if isLast {
                    onFinish()
                } else {
                    model.page += 1
                }
            }
            .buttonStyle(PillButtonStyle(primary: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var calendarStatus: OnboardingModel.Status {
        switch calendar.access {
        case .granted: return .granted
        case .denied: return .denied
        case .notDetermined: return .pending
        }
    }
}

struct TourRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.red)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.red.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: OnboardingModel.Status
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.blue.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            switch status {
            case .granted:
                Label(tr("Aktif", "Allowed"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.green)
            case .denied:
                Text(tr("Ditolak", "Denied"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.amber)
            case .requested:
                Text(tr("Diminta", "Requested"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            case .pending:
                Button(tr("Izinkan", "Allow"), action: action)
                    .buttonStyle(PillButtonStyle(primary: true))
            }
        }
        .frame(height: 38)
    }
}

/// Standalone onboarding window centered on the screen.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?

    /// Brings the window back to the front after a macOS permission prompt closes.
    func bringToFront() {
        guard let window else { return }
        window.orderFrontRegardless()
        window.makeKey()
    }

    func show(rootView: AnyView) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.bringToFront()
            }
        }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
        window = nil
        onClose?()
    }
}
