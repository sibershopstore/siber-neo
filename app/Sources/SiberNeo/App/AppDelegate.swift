import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let state = NotchState()
    let media = MediaController()
    let focus = FocusTimer()
    let todos = TodoStore()
    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let prayer = PrayerService()
    let power = PowerService()
    let bluetooth = BluetoothWatcher()
    let mascot = MascotController()
    let hud = SystemHUDService()
    let privacy = PrivacyMonitor()
    let network = NetworkMonitor()
    let calendar = CalendarService()
    let presentation = PresentationMonitor()
    let habits = HabitStore()
    let weather = WeatherService()
    let screenshots = ScreenshotWatcher()
    let preferences = AppPreferences()
    let greetings = GreetingService()
    let achievements = AchievementStore()
    let updates = UpdateService()
    private var whatsNewWindow: OnboardingWindowController?
    let onboardingModel = OnboardingModel()
    private var onboardingWindow: OnboardingWindowController?
    private var deferredStarted = false

    private var windowController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        let root = NotchRootView()
            .environmentObject(state)
            .environmentObject(media)
            .environmentObject(focus)
            .environmentObject(todos)
            .environmentObject(shelf)
            .environmentObject(clipboard)
            .environmentObject(prayer)
            .environmentObject(power)
            .environmentObject(mascot)
            .environmentObject(privacy)
            .environmentObject(network)
            .environmentObject(calendar)
            .environmentObject(presentation)
            .environmentObject(habits)
            .environmentObject(weather)
            .environmentObject(preferences)
            .environmentObject(EnergyMode.shared)
            .environmentObject(achievements)
            .environmentObject(updates)
            .environment(\.colorScheme, .dark)

        let controller = NotchWindowController(state: state, rootView: AnyView(root))
        let mascot = self.mascot
        controller.onMouseActivity = { position in
            mascot.noteActivity(position: position)
        }
        let notchState = self.state
        let calendarService = self.calendar
        let focusTimer = self.focus
        let mediaController = self.media
        let habitStore = self.habits
        controller.onOpen = {
            if mascot.mood == .asleep || mascot.mood == .sleepy {
                mascot.greet()
            }
            if Self.smartTabsEnabled,
               let tab = Self.contextualTab(calendar: calendarService, focus: focusTimer, media: mediaController, habits: habitStore) {
                notchState.tab = tab
            }
        }
        windowController = controller
        setupStatusItem()
        state.openSettingsMenu = { [weak self] in
            MainActor.assumeIsolated {
                self?.popUpSettingsMenu()
            }
        }
        wireEvents()
        hud.start()
        privacy.start()
        network.start()
        presentation.start()
        weather.start(city: prayer.city)

        if OnboardingModel.isCompleted {
            startDeferredServices()
            if UserDefaults.standard.string(forKey: ReleaseNotes.lastSeenKey) != UpdateService.currentVersion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.showWhatsNew()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    // MARK: - Onboarding

    /// Services that trigger macOS permission prompts, started after onboarding is complete.
    private func startDeferredServices() {
        guard !deferredStarted else { return }
        deferredStarted = true
        Notifier.requestAuthorization()
        bluetooth.start()
        screenshots.start()
        media.startYouTube()
        greetings.start()
        updates.start()
    }

    // MARK: - What's new

    private func showWhatsNew() {
        UserDefaults.standard.set(UpdateService.currentVersion, forKey: ReleaseNotes.lastSeenKey)
        let controller = whatsNewWindow ?? OnboardingWindowController()
        let view = WhatsNewView(onClose: { [weak controller] in
            MainActor.assumeIsolated {
                controller?.close()
            }
        })
        .environmentObject(mascot)
        whatsNewWindow = controller
        controller.show(rootView: AnyView(view))
    }

    @objc private func openWhatsNew() {
        showWhatsNew()
    }

    // MARK: - Updates

    @objc private func downloadUpdate() {
        updates.openDownload()
    }

    @objc private func skipUpdate() {
        updates.skipCurrent()
    }

    @objc private func checkForUpdates() {
        updates.check(userInitiated: true) { [weak self] result in
            MainActor.assumeIsolated {
                self?.presentUpdateResult(result)
            }
        }
    }

    private func presentUpdateResult(_ result: UpdateService.CheckResult) {
        let alert = NSAlert()
        switch result {
        case .upToDate:
            alert.messageText = tr("Siber Neo sudah versi terbaru", "Siber Neo is up to date")
            alert.informativeText = tr("Versi \(UpdateService.currentVersion) adalah versi terbaru.", "Version \(UpdateService.currentVersion) is the latest.")
            alert.addButton(withTitle: "OK")
        case .available(let info):
            alert.messageText = tr("Siber Neo \(info.version) tersedia", "Siber Neo \(info.version) is available")
            let notes = info.localizedNotes.map { "• \($0)" }.joined(separator: "\n")
            alert.informativeText = notes.isEmpty
                ? tr("Unduh versi terbaru dari situs resmi.", "Download the latest version from the official site.")
                : notes
            alert.addButton(withTitle: tr("Unduh", "Download"))
            alert.addButton(withTitle: tr("Nanti", "Later"))
        case .failed:
            alert.messageText = tr("Tidak dapat memeriksa pembaruan", "Couldn't check for updates")
            alert.informativeText = tr("Periksa koneksi internet, lalu coba lagi.", "Check your internet connection and try again.")
            alert.addButton(withTitle: "OK")
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if case .available = result, response == .alertFirstButtonReturn {
            updates.openDownload()
        }
    }

    private func showOnboarding() {
        let model = onboardingModel
        model.page = 0

        let bluetooth = self.bluetooth
        let screenshots = self.screenshots
        let media = self.media
        model.requestBluetoothAction = {
            bluetooth.start()
        }
        model.requestFolderAction = { [weak model] in
            let directory = ScreenshotWatcher.screenshotDirectory()
            DispatchQueue.global(qos: .userInitiated).async {
                let allowed = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) != nil
                DispatchQueue.main.async {
                    model?.folder = allowed ? .granted : .denied
                    if allowed { screenshots.start() }
                    model?.afterRequest?()
                }
            }
        }
        model.requestAutomationAction = {
            media.startYouTube()
        }

        let view = OnboardingView(model: model, onFinish: { [weak self] in
            MainActor.assumeIsolated {
                self?.finishOnboarding()
            }
        })
        .environmentObject(mascot)
        .environmentObject(calendar)
        .environmentObject(network)
        .environmentObject(prayer)

        let controller = onboardingWindow ?? OnboardingWindowController()
        model.afterRequest = { [weak controller] in
            MainActor.assumeIsolated {
                controller?.bringToFront()
            }
        }
        controller.onClose = { [weak self] in
            MainActor.assumeIsolated {
                self?.finishOnboarding()
            }
        }
        onboardingWindow = controller
        controller.show(rootView: AnyView(view))
    }

    private func finishOnboarding() {
        let firstTime = !OnboardingModel.isCompleted
        OnboardingModel.isCompleted = true
        onboardingWindow?.onClose = nil
        onboardingWindow?.close()
        startDeferredServices()
        if firstTime {
            UserDefaults.standard.set(UpdateService.currentVersion, forKey: ReleaseNotes.lastSeenKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.greetings.greetIfNeeded(force: true)
            }
        }
    }

    @objc private func openOnboarding() {
        showOnboarding()
    }

    // MARK: - Event wiring

    private func wireEvents() {
        let state = self.state
        let media = self.media
        let prayer = self.prayer

        let mascot = self.mascot

        Publishers.CombineLatest4(media.$track, focus.$isRunning, mascot.$enabled, privacy.$isActive)
            .receive(on: DispatchQueue.main)
            .sink { track, focusRunning, mascotEnabled, privacyActive in
                if focusRunning {
                    state.live = .focus
                } else if track?.isPlaying == true {
                    state.live = .media
                } else if mascotEnabled {
                    state.live = .mascot
                } else if privacyActive {
                    state.live = .privacy
                } else {
                    state.live = nil
                }
            }
            .store(in: &cancellables)

        presentation.$isActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { active in
                state.quiet = active
                Notifier.isMuted = active
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(mascot.$message, mascot.$mood)
            .receive(on: DispatchQueue.main)
            .sink { message, _ in
                if let message {
                    state.liveWing = max(52, Fmt.textWidth(message, size: 11, weight: .semibold) + 24)
                } else {
                    state.liveWing = 52
                }
            }
            .store(in: &cancellables)

        let energy = EnergyMode.shared

        Publishers.CombineLatest(power.$percent, power.$onAC)
            .receive(on: DispatchQueue.main)
            .sink { percent, onAC in
                mascot.lowBattery = !onAC && (percent ?? 100) <= 20
                energy.updateBattery(percent: percent, onAC: onAC)
            }
            .store(in: &cancellables)

        energy.$isSaving
            .receive(on: DispatchQueue.main)
            .sink { saving in
                mascot.reducedMotion = saving
            }
            .store(in: &cancellables)

        energy.onChange = { saving in
            guard saving else { return }
            state.show(NotchActivity(
                icon: "leaf.fill",
                tint: Theme.green,
                title: tr("Mode hemat energi", "Energy saver"),
                detail: tr("Animasi dikurangi", "Animations reduced")
            ), for: 3)
        }

        hud.onVolume = { volume, muted in
            let level = muted ? 0 : Double(volume)
            let icon: String
            if muted || level < 0.01 {
                icon = "speaker.slash.fill"
            } else if level < 0.34 {
                icon = "speaker.wave.1.fill"
            } else if level < 0.67 {
                icon = "speaker.wave.2.fill"
            } else {
                icon = "speaker.wave.3.fill"
            }
            state.show(NotchActivity(icon: icon, tint: .white, title: muted ? tr("Bisu", "Muted") : "Volume", detail: "", level: level), for: 1.6)
        }

        hud.onBrightness = { brightness in
            state.show(NotchActivity(
                icon: "sun.max.fill",
                tint: Color(red: 1.0, green: 0.82, blue: 0.35),
                title: tr("Kecerahan", "Brightness"),
                detail: "",
                level: Double(brightness)
            ), for: 1.6)
        }

        hud.onCapsLock = { isOn in
            state.show(NotchActivity(
                icon: isOn ? "capslock.fill" : "capslock",
                tint: isOn ? Theme.blue : Theme.secondary,
                title: isOn ? tr("Caps Lock aktif", "Caps Lock on") : tr("Caps Lock nonaktif", "Caps Lock off"),
                detail: ""
            ), for: 1.4)
        }

        hud.onInputSource = { name in
            state.show(NotchActivity(icon: "globe", tint: Theme.blue, title: "Keyboard", detail: name), for: 1.6)
        }

        privacy.onCameraChange = { isOn in
            state.show(NotchActivity(
                icon: isOn ? "video.fill" : "video.slash.fill",
                tint: isOn ? Theme.red : Theme.secondary,
                title: isOn ? tr("Kamera aktif", "Camera on") : tr("Kamera nonaktif", "Camera off"),
                detail: isOn ? tr("Sedang digunakan", "In use") : ""
            ), for: isOn ? 4 : 2)
        }

        privacy.onMicChange = { isOn, apps in
            state.show(NotchActivity(
                icon: isOn ? "mic.fill" : "mic.slash.fill",
                tint: isOn ? Theme.amber : Theme.secondary,
                title: isOn ? tr("Mikrofon aktif", "Microphone on") : tr("Mikrofon nonaktif", "Microphone off"),
                detail: isOn ? (apps.first ?? tr("Sedang digunakan", "In use")) : ""
            ), for: isOn ? 4 : 2)
        }

        network.onChange = { previous, current in
            if current.isRisky && !previous.isRisky {
                state.show(NotchActivity(
                    icon: "wifi.exclamationmark",
                    tint: Theme.red,
                    title: tr("Wi-Fi tanpa enkripsi", "Unencrypted Wi-Fi"),
                    detail: current.ssid ?? tr("Hati-hati", "Be careful")
                ), for: 8)
                Notifier.post(
                    title: tr("Jaringan tidak aman", "Insecure network"),
                    body: tr("Wi-Fi yang terhubung tidak terenkripsi. Hindari mengakses data sensitif atau aktifkan VPN.", "The connected Wi-Fi is not encrypted. Avoid accessing sensitive data or turn on a VPN.")
                )
            } else if current.vpnActive != previous.vpnActive {
                state.show(NotchActivity(
                    icon: current.vpnActive ? "lock.shield.fill" : "lock.open.fill",
                    tint: current.vpnActive ? Theme.green : Theme.amber,
                    title: current.vpnActive ? tr("VPN aktif", "VPN connected") : tr("VPN terputus", "VPN disconnected"),
                    detail: ""
                ), for: 3)
            } else if previous.isConnected && !current.isConnected {
                state.show(NotchActivity(icon: "wifi.slash", tint: Theme.secondary, title: tr("Koneksi terputus", "Connection lost"), detail: ""), for: 3)
            }
        }

        calendar.onSoon = { event in
            state.show(NotchActivity(icon: "calendar", tint: Theme.blue, title: event.title, detail: tr("5 menit lagi", "In 5 minutes")), for: 8)
            Notifier.post(title: tr("Agenda dalam 5 menit", "Event in 5 minutes"), body: event.title)
            Notifier.chime()
        }

        prayer.$city
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak weather = self.weather] city in
                weather?.update(city: city)
            }
            .store(in: &cancellables)

        weather.onRainSoon = { chance in
            state.show(NotchActivity(
                icon: "cloud.rain.fill",
                tint: Theme.blue,
                title: tr("Kemungkinan hujan", "Rain likely"),
                detail: tr("\(chance)% dalam 1–2 jam", "\(chance)% in 1–2 hours")
            ), for: 8)
            Notifier.post(title: tr("Kemungkinan hujan", "Rain likely"), body: tr("Peluang hujan \(chance)% dalam 1–2 jam ke depan.", "\(chance)% chance of rain in the next 1–2 hours."))
        }

        let shelf = self.shelf
        screenshots.onScreenshot = { url in
            shelf.add(url)
            state.show(NotchActivity(icon: "camera.viewfinder", tint: Theme.blue, title: tr("Screenshot masuk Shelf", "Screenshot added to Shelf"), detail: tr("Siap ditarik", "Ready to drag")), for: 3)
        }

        updates.onAvailable = { info in
            state.show(NotchActivity(
                icon: "arrow.down.circle.fill",
                tint: Theme.blue,
                title: tr("Pembaruan tersedia", "Update available"),
                detail: "Siber Neo \(info.version)"
            ), for: 8)
            Notifier.post(
                title: tr("Siber Neo \(info.version) tersedia", "Siber Neo \(info.version) is available"),
                body: tr("Klik tombol unduh di notch untuk memperbarui.", "Click the download button in the notch to update.")
            )
            mascot.greet()
        }

        greetings.onGreeting = { greeting in
            state.show(NotchActivity(
                icon: greeting.icon,
                tint: Color(red: 1.0, green: 0.78, blue: 0.35),
                title: greeting.title,
                detail: greeting.detail
            ), for: 5)
            mascot.greet()
            if UserProfile.isBirthday() {
                mascot.refreshBirthday()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    state.launchConfetti()
                }
            }
        }

        Publishers.CombineLatest(focus.$isRunning, focus.$phase)
            .receive(on: DispatchQueue.main)
            .sink { running, phase in
                mascot.isFocusing = running && phase == .focus
            }
            .store(in: &cancellables)

        mascot.onStretch = {
            state.show(NotchActivity(
                icon: "figure.cooldown",
                tint: Theme.green,
                title: tr("Waktunya peregangan", "Time to stretch"),
                detail: tr("30 detik saja", "Just 30 seconds")
            ), for: 4)
            Notifier.post(
                title: tr("Waktunya peregangan", "Time to stretch"),
                body: tr("Sudah 1 jam aktif. Berdiri dan regangkan badan sejenak.", "You've been active for an hour. Stand up and stretch for a moment.")
            )
        }

        state.$isDropTargeted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { targeted in
                mascot.setEating(targeted)
            }
            .store(in: &cancellables)

        let achievements = self.achievements
        let habits = self.habits

        habits.onAdd = { kind in
            mascot.react(to: kind)
            if kind == .water, habits.count(.water) == habits.waterGoal {
                achievements.recordWaterGoal(dayKey: HabitStore.key(for: Date()))
            }
        }

        achievements.$equipped
            .receive(on: DispatchQueue.main)
            .sink { accessory in
                mascot.accessory = accessory
            }
            .store(in: &cancellables)

        achievements.onUnlock = { accessory in
            state.show(NotchActivity(
                icon: accessory.symbol,
                tint: Color(red: 1.0, green: 0.82, blue: 0.4),
                title: tr("Aksesori baru untuk \(UserProfile.mascotName)", "New accessory for \(UserProfile.mascotName)"),
                detail: accessory.title
            ), for: 6)
            Notifier.post(
                title: tr("Aksesori baru untuk \(UserProfile.mascotName)", "New accessory for \(UserProfile.mascotName)"),
                body: tr("\(accessory.title) terbuka. Pakaikan dari tab Keamanan.", "\(accessory.title) unlocked. Put it on from the Security tab.")
            )
            mascot.celebrate()
            UISound.unlock.play()
        }

        weather.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { snapshot in
                mascot.weatherOutfit = MascotController.outfit(for: snapshot)
            }
            .store(in: &cancellables)

        mascot.onLateNight = {
            state.show(NotchActivity(
                icon: "moon.zzz.fill",
                tint: MascotView.accentText,
                title: tr("Sudah larut malam", "It's getting late"),
                detail: tr("Waktunya istirahat", "Time to rest")
            ), for: 5)
        }

        habits.onReminder = { kind, detail in
            let title = kind == .water ? tr("Waktunya minum air", "Time to drink water") : tr("Waktunya camilan", "Snack time")
            state.show(NotchActivity(icon: kind.icon, tint: kind.tint, title: title, detail: detail), for: 8)
            Notifier.post(title: title, body: kind == .water ? tr("Progres hari ini: \(detail).", "Today's progress: \(detail).") : tr("Ambil jeda sejenak.", "Take a short break."))
            Notifier.chime()
        }

        habits.onLimit = { kind, count, limit in
            let title = count > limit ? tr("Melewati batas \(kind.title.lowercased())", "Over your \(kind.title.lowercased()) limit") : tr("Batas \(kind.title.lowercased()) tercapai", "\(kind.title) limit reached")
            state.show(NotchActivity(
                icon: kind.icon,
                tint: Theme.amber,
                title: title,
                detail: "\(count)/\(limit) \(kind.unit)"
            ), for: 5)
        }

        power.onLowBattery = { percent in
            state.show(NotchActivity(icon: "battery.25", tint: Theme.red, title: tr("Baterai lemah", "Low battery"), detail: "\(percent)%"), for: 6)
        }

        focus.onPhaseEnd = { phase in
            let finishedFocus = phase == .focus
            if finishedFocus {
                achievements.recordFocusSession()
                mascot.startStretch(duration: 20)
            }
            state.show(NotchActivity(
                icon: finishedFocus ? "cup.and.saucer.fill" : "timer",
                tint: finishedFocus ? Theme.blue : Theme.red,
                title: finishedFocus ? tr("Sesi fokus selesai", "Focus session done") : tr("Istirahat selesai", "Break is over"),
                detail: finishedFocus ? tr("Istirahat", "Break") : tr("Siap fokus", "Ready to focus")
            ), for: 6)
            Notifier.post(
                title: finishedFocus ? tr("Sesi fokus selesai", "Focus session done") : tr("Istirahat selesai", "Break is over"),
                body: finishedFocus ? tr("Saatnya mengambil jeda sejenak.", "Time to take a short break.") : tr("Siap untuk sesi fokus berikutnya.", "Ready for the next focus session.")
            )
            Notifier.chime()
        }

        todos.onDue = { item in
            state.show(NotchActivity(icon: "bell.fill", tint: Theme.red, title: item.title, detail: tr("Pengingat", "Reminder")), for: 8)
            Notifier.post(title: tr("Pengingat tugas", "Task reminder"), body: item.title)
            Notifier.chime()
        }

        prayer.onPrayerTime = { [weak prayer] time in
            guard let prayer else { return }
            if prayer.pauseMediaOnAdhan {
                media.pause()
            }
            let clock = Fmt.clock(time.date, timeZone: prayer.city.timeZone)
            state.show(NotchActivity(icon: "moon.stars.fill", tint: Theme.red, title: tr("Waktu \(time.name.title)", "\(time.name.title) time"), detail: clock), for: 10)
            Notifier.post(title: tr("Waktu \(time.name.title)", "\(time.name.title) time"), body: "\(prayer.city.name), \(clock)")
        }

        power.onPluggedIn = { percent in
            state.show(NotchActivity(
                icon: "bolt.fill",
                tint: Theme.green,
                title: tr("Mengisi daya", "Charging"),
                detail: "",
                level: Double(percent ?? 0) / 100,
                charging: true
            ), for: 3.5)
        }

        bluetooth.onEvent = { name, connected in
            state.show(NotchActivity(
                icon: "headphones",
                tint: connected ? Theme.blue : Theme.secondary,
                title: name,
                detail: connected ? tr("Terhubung", "Connected") : tr("Terputus", "Disconnected")
            ))
        }
    }

    // MARK: - Status bar menu

    /// Hidden main menu so copy, paste, and undo shortcuts keep working in text fields.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Keluar", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    /// Shows the settings menu at the cursor, for Macs whose menu bar icon is hidden by the notch.
    private func popUpSettingsMenu() {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        state.keepOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        state.keepOpen = false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Siber Neo")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Siber Neo \(Self.version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let info = updates.available {
            let download = NSMenuItem(title: tr("Unduh Siber Neo \(info.version)", "Download Siber Neo \(info.version)"), action: #selector(downloadUpdate), keyEquivalent: "")
            download.target = self
            menu.addItem(download)
            let skip = NSMenuItem(title: tr("Lewati versi ini", "Skip this version"), action: #selector(skipUpdate), keyEquivalent: "")
            skip.target = self
            menu.addItem(skip)
        }
        menu.addItem(.separator())

        menu.addItem(toggleItem(tr("Buka saat login", "Open at login"), isOn: SMAppService.mainApp.status == .enabled, action: #selector(toggleLaunchAtLogin)))
        menu.addItem(toggleItem(tr("Tab pintar", "Smart tabs"), isOn: Self.smartTabsEnabled, action: #selector(toggleSmartTabs)))
        menu.addItem(toggleItem(tr("Mode presentasi", "Presentation mode"), isOn: presentation.manual, action: #selector(togglePresentation)))
        menu.addItem(toggleItem(tr("Mode presentasi otomatis", "Automatic presentation mode"), isOn: presentation.autoEnabled, action: #selector(togglePresentationAuto)))
        menu.addItem(toggleItem(tr("Screenshot otomatis ke Shelf", "Auto-add screenshots to Shelf"), isOn: preferences.screenshotShelf, action: #selector(toggleScreenshotShelf)))
        menu.addItem(toggleItem(tr("Hemat energi otomatis", "Automatic energy saver"), isOn: EnergyMode.shared.autoEnabled, action: #selector(toggleEnergySaver)))
        menu.addItem(toggleItem(tr("Suara antarmuka", "Interface sounds"), isOn: UISound.enabled, action: #selector(toggleSounds)))
        menu.addItem(.separator())
        menu.addItem(toggleItem(tr("Maskot \(UserProfile.mascotName)", "\(UserProfile.mascotName) mascot"), isOn: mascot.enabled, action: #selector(toggleMascot)))

        let renameItem = NSMenuItem(title: tr("Ganti nama maskot…", "Rename mascot…"), action: #selector(renameMascot), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        let birthdayItem = NSMenuItem(title: tr("Atur tanggal ulang tahun…", "Set your birthday…"), action: #selector(setBirthday), keyEquivalent: "")
        birthdayItem.target = self
        menu.addItem(birthdayItem)

        let paletteItem = NSMenuItem(title: tr("Warna \(UserProfile.mascotName)", "\(UserProfile.mascotName) color"), action: nil, keyEquivalent: "")
        let paletteMenu = NSMenu()
        for palette in MascotPalette.allCases {
            let item = NSMenuItem(title: palette.title, action: #selector(selectPalette(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = palette.rawValue
            item.state = palette == mascot.palette ? .on : .off
            paletteMenu.addItem(item)
        }
        paletteItem.submenu = paletteMenu
        menu.addItem(paletteItem)
        menu.addItem(.separator())

        let cityItem = NSMenuItem(title: tr("Kota: \(prayer.city.name)", "City: \(prayer.city.name)"), action: nil, keyEquivalent: "")
        let cityMenu = NSMenu()
        for city in City.all {
            let item = NSMenuItem(title: city.name, action: #selector(selectCity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = city.name
            item.state = city.name == prayer.city.name ? .on : .off
            cityMenu.addItem(item)
        }
        cityItem.submenu = cityMenu
        menu.addItem(cityItem)
        menu.addItem(toggleItem(tr("Pengingat waktu sholat", "Prayer time reminders"), isOn: prayer.remindersEnabled, action: #selector(toggleReminders)))
        menu.addItem(toggleItem(tr("Jeda musik saat adzan", "Pause music at prayer time"), isOn: prayer.pauseMediaOnAdhan, action: #selector(togglePauseMedia)))
        menu.addItem(.separator())

        let languageItem = NSMenuItem(title: "Bahasa / Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        let languages: [(Lang.Choice, String)] = [
            (.auto, tr("Ikuti sistem", "Follow system")),
            (.id, "Bahasa Indonesia"),
            (.en, "English")
        ]
        for (choice, title) in languages {
            let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == Lang.choice ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(.separator())

        let guide = NSMenuItem(title: tr("Panduan awal", "Getting started"), action: #selector(openOnboarding), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)
        let whatsNew = NSMenuItem(title: tr("Yang baru di versi ini", "What's new in this version"), action: #selector(openWhatsNew), keyEquivalent: "")
        whatsNew.target = self
        menu.addItem(whatsNew)
        let check = NSMenuItem(title: tr("Periksa pembaruan…", "Check for updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        menu.addItem(NSMenuItem(title: tr("Keluar", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func toggleItem(_ title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return item
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Siber Neo: gagal mengubah pengaturan login item: \(error.localizedDescription)")
        }
    }

    @objc private func selectCity(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let city = City.all.first(where: { $0.name == name }) else { return }
        prayer.city = city
    }

    /// The language is applied at launch, so the app relaunches automatically.
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, raw != Lang.choice.rawValue else { return }
        UserDefaults.standard.set(raw, forKey: "appLanguage")
        relaunch()
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func renameMascot() {
        let alert = NSAlert()
        alert.messageText = tr("Ganti nama maskot", "Rename mascot")
        alert.informativeText = tr("Nama ini dipakai di seluruh sapaan dan tampilan.", "This name is used across greetings and the interface.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = UserProfile.mascotName
        field.placeholderString = UserProfile.defaultMascotName
        alert.accessoryView = field
        alert.addButton(withTitle: tr("Simpan", "Save"))
        alert.addButton(withTitle: tr("Batal", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserProfile.mascotName = field.stringValue
        mascot.greet()
    }

    @objc private func setBirthday() {
        let alert = NSAlert()
        alert.messageText = tr("Tanggal ulang tahun", "Your birthday")
        alert.informativeText = tr("\(UserProfile.mascotName) akan merayakannya setiap tahun. Data hanya disimpan di Mac ini.", "\(UserProfile.mascotName) will celebrate it every year. Stored only on this Mac.")
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .yearMonthDay
        picker.locale = Lang.locale
        if let birthday = UserProfile.birthday,
           let date = Calendar.current.date(from: DateComponents(year: 2000, month: birthday.month, day: birthday.day)) {
            picker.dateValue = date
        } else {
            picker.dateValue = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()
        }
        alert.accessoryView = picker
        alert.addButton(withTitle: tr("Simpan", "Save"))
        alert.addButton(withTitle: tr("Batal", "Cancel"))
        alert.addButton(withTitle: tr("Hapus", "Remove"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let parts = Calendar.current.dateComponents([.month, .day], from: picker.dateValue)
            if let month = parts.month, let day = parts.day {
                UserProfile.birthday = (month, day)
            }
        case .alertThirdButtonReturn:
            UserProfile.birthday = nil
        default:
            return
        }
        mascot.refreshBirthday()
        if UserProfile.isBirthday() {
            state.launchConfetti()
        }
    }

    @objc private func toggleSounds() {
        UISound.enabled.toggle()
        UISound.open.play()
    }

    @objc private func toggleEnergySaver() {
        EnergyMode.shared.autoEnabled.toggle()
    }

    @objc private func toggleScreenshotShelf() {
        preferences.screenshotShelf.toggle()
    }

    @objc private func toggleSmartTabs() {
        Self.smartTabsEnabled.toggle()
    }

    @objc private func togglePresentation() {
        presentation.manual.toggle()
    }

    @objc private func togglePresentationAuto() {
        presentation.autoEnabled.toggle()
    }

    // MARK: - Smart tabs

    nonisolated static var smartTabsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "smartTabs") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "smartTabs") }
    }

    /// The most relevant tab when the notch opens: an event that is about to start or just started,
    /// a running focus timer, then the music currently playing.
    nonisolated static func contextualTab(calendar: CalendarService, focus: FocusTimer, media: MediaController, habits: HabitStore) -> NotchTab? {
        let now = Date()
        if let reminder = habits.lastReminder, now.timeIntervalSince(reminder) < 10 * 60 {
            return .habits
        }
        if let event = calendar.events.first(where: { $0.end > now }) {
            let untilStart = event.start.timeIntervalSince(now)
            if untilStart <= 10 * 60, untilStart >= -10 * 60 {
                return .agenda
            }
        }
        if focus.isRunning { return .focus }
        if media.track?.isPlaying == true { return .media }
        return nil
    }

    @objc private func toggleMascot() {
        mascot.enabled.toggle()
    }

    @objc private func selectPalette(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let palette = MascotPalette(rawValue: raw) else { return }
        mascot.palette = palette
        mascot.poke()
    }

    @objc private func toggleReminders() {
        prayer.remindersEnabled.toggle()
    }

    @objc private func togglePauseMedia() {
        prayer.pauseMediaOnAdhan.toggle()
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
