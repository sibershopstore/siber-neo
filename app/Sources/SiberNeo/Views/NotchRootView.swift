import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var mascot: MascotController
    @EnvironmentObject var media: MediaController

    var body: some View {
        let mode = state.mode
        let size = state.currentSize
        let topRadius: CGFloat = mode == .open ? 12 : 6
        let bottomRadius: CGFloat = mode == .open ? 24 : (mode == .closed ? 10 : 14)
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        let shelfStore = shelf

        let glow = glowColor(mode: mode)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(mode == .open ? 0.55 : 0), radius: 18, y: 8)
                .shadow(color: (glow ?? .clear).opacity(glow == nil ? 0 : (mode == .open ? 0.45 : 0.6)), radius: mode == .open ? 22 : 10)

            if let glow, mode == .open {
                shape
                    .fill(
                        RadialGradient(
                            colors: [glow.opacity(0.22), .clear],
                            center: .bottom,
                            startRadius: 0,
                            endRadius: size.width * 0.55
                        )
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            Group {
                switch mode {
                case .open:
                    OpenNotchView()
                case .activity:
                    ActivityView()
                case .live:
                    LiveView()
                case .closed:
                    Color.clear
                }
            }
            .padding(.horizontal, topRadius)
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .transition(.blurFade)

            if state.isDropTargeted {
                shape
                    .stroke(Theme.red.opacity(0.8), lineWidth: 1.5)
                    .allowsHitTesting(false)
                if mode == .open {
                    DropFeedView()
                        .frame(width: size.width, height: size.height)
                        .clipShape(shape)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onDrop(of: [UTType.fileURL], isTargeted: $state.isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        shelfStore.add(url)
                    }
                }
            }
            state.tab = .shelf
            mascot.chomp()
            UISound.drop.play()
            return true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: mode)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: size)
        .animation(.easeInOut(duration: 0.6), value: glow)
        .overlay(alignment: .top) {
            if !state.confetti.isEmpty {
                ConfettiLayer(
                    particles: state.confetti,
                    start: state.confettiStart,
                    notchWidth: state.notchSize.width,
                    notchHeight: state.notchSize.height
                )
            }
        }
        .foregroundStyle(.white)
    }
}

extension NotchRootView {
    /// Album color glow while music plays in live view or in the Music tab.
    func glowColor(mode: NotchMode) -> Color? {
        if mode == .activity, state.activity?.charging == true {
            return Theme.green
        }
        guard let accent = media.accentColor, media.track != nil else { return nil }
        switch mode {
        case .activity:
            return nil
        case .live:
            return state.live == .media ? accent : nil
        case .open:
            return state.tab == .media ? accent : nil
        default:
            return nil
        }
    }
}

/// Neo opens its mouth waiting for a file while it is dragged over the notch.
struct DropFeedView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            VStack(spacing: 10) {
                MascotView(size: 68)
                    .frame(height: 70)
                Text(tr("Lepaskan, \(UserProfile.mascotName) akan menyimpannya di Shelf", "Drop it, \(UserProfile.mascotName) will keep it in the Shelf"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// Compact view while the notch is closed: Neo, music, focus timer, or privacy indicator.
struct LiveView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var focus: FocusTimer
    @EnvironmentObject var mascot: MascotController
    @EnvironmentObject var privacy: PrivacyMonitor
    @EnvironmentObject var energy: EnergyMode

    var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: state.notchSize.width)
            HStack(spacing: 6) {
                if privacy.isActive, state.live != .privacy {
                    PrivacyDots()
                }
                trailing
            }
        }
        .padding(.horizontal, 10)
        .frame(height: state.notchSize.height)
    }

    @ViewBuilder
    private var leading: some View {
        switch state.live ?? .media {
        case .mascot:
            MascotView(size: 24)
        case .focus:
            if mascot.enabled {
                MascotView(size: 24)
            } else {
                Image(systemName: focus.phase == .focus ? "timer" : "cup.and.saucer.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(focus.phase == .focus ? Theme.red : Theme.blue)
            }
        case .privacy:
            Image(systemName: privacy.cameraActive ? "video.fill" : "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(privacy.cameraActive ? Theme.red : Theme.amber)
        case .media:
            ZStack {
                ArtworkView(image: media.track?.artwork, size: 20, radius: 5)
                    .id(media.track?.trackKey ?? "")
                    .transition(.cardFlip)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: media.track?.trackKey)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state.live ?? .media {
        case .mascot:
            if let message = mascot.message {
                Text(message)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MascotView.accentText)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity)
            } else {
                switch mascot.mood {
                case .asleep:
                    SleepingZView()
                case .tired:
                    Image(systemName: "battery.25")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                default:
                    Color.clear.frame(width: 1, height: 1)
                }
            }
        case .focus:
            Text(Fmt.mmss(focus.remaining))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        case .privacy:
            PrivacyDots()
        case .media:
            if mascot.enabled {
                MascotView(size: 21, dancing: (media.track?.isPlaying ?? false) && !energy.isSaving)
            } else {
                EqualizerView(playing: (media.track?.isPlaying ?? false) && !energy.isSaving, color: media.accentColor ?? Theme.red)
            }
        }
    }
}

/// Indicator dot: red for the camera, orange for the microphone.
struct PrivacyDots: View {
    @EnvironmentObject var privacy: PrivacyMonitor

    var body: some View {
        HStack(spacing: 3) {
            if privacy.cameraActive {
                Circle().fill(Theme.red).frame(width: 6, height: 6)
                    .shadow(color: Theme.red, radius: 3)
            }
            if privacy.micActive {
                Circle().fill(Theme.amber).frame(width: 6, height: 6)
                    .shadow(color: Theme.amber, radius: 3)
            }
        }
    }
}

/// Brief notification shown on the left and right sides of the notch.
struct ActivityView: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        if let activity = state.activity {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: activity.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(activity.tint)
                    Text(activity.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: state.notchSize.width + 12)
                if activity.charging {
                    ChargingBatteryView(level: activity.level ?? 0)
                        .id(activity.id)
                } else if let level = activity.level {
                    LevelBar(value: level, tint: activity.tint)
                } else {
                    Text(activity.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: state.notchSize.height)
        }
    }
}

/// Level bar for volume and brightness.
struct LevelBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        let clamped = min(max(value, 0), 1)
        HStack(spacing: 7) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(tint).frame(width: 72 * CGFloat(clamped))
            }
            .frame(width: 72, height: 5)
            .animation(.easeOut(duration: 0.15), value: clamped)
            Text("\(Int((clamped * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

struct OpenNotchView: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
                .frame(height: max(state.notchSize.height, 30))
                .staggeredAppear(delay: 0.03)

            ZStack {
                tabContent
                    .id(state.tab)
                    .transition(.tabSlide(forward: state.tabForward))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .clipped()
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: state.tab)
            .staggeredAppear(delay: 0.09)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch state.tab {
            case .media: MediaTabView()
            case .focus: FocusTabView()
            case .todo: TodoTabView()
            case .agenda: AgendaTabView()
            case .habits: HabitTabView()
            case .shelf: ShelfTabView()
            case .prayer: PrayerTabView()
            case .security: SecurityTabView()
            case .weather: WeatherTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeaderBar: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var power: PowerService
    @EnvironmentObject var privacy: PrivacyMonitor
    @EnvironmentObject var presentation: PresentationMonitor
    @EnvironmentObject var updates: UpdateService
    @Namespace var tabIndicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.tabBarCases, id: \.self) { tab in
                Button {
                    state.tab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.tab == tab ? Theme.red : Theme.secondary)
                        .frame(width: 26, height: 22)
                        .background {
                            if state.tab == tab {
                                Capsule()
                                    .fill(Theme.red.opacity(0.16))
                                    .matchedGeometryEffect(id: "tab", in: tabIndicator)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }

            Spacer(minLength: state.notchSize.width + 16)

            if privacy.isActive {
                HStack(spacing: 4) {
                    if privacy.cameraActive {
                        Image(systemName: "video.fill").foregroundStyle(Theme.red)
                    }
                    if privacy.micActive {
                        Image(systemName: "mic.fill").foregroundStyle(Theme.amber)
                    }
                }
                .font(.system(size: 10))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .padding(.trailing, 8)
                .onTapGesture { state.tab = .security }
            }

            if let info = updates.available {
                Button {
                    updates.openDownload()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(info.version)
                            .monospacedDigit()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.blue))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tr("Unduh Siber Neo \(info.version)", "Download Siber Neo \(info.version)"))
                .padding(.trailing, 6)
            }

            WeatherChip()

            Button {
                presentation.manual.toggle()
            } label: {
                Image(systemName: presentation.isActive ? "eye.slash.fill" : "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(presentation.isActive ? Theme.red : Theme.tertiary)
                    .frame(width: 24, height: 22)
                    .background(Capsule().fill(presentation.isActive ? Theme.red.opacity(0.16) : Color.clear))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(Text(presentation.isActive ? tr("Mode presentasi aktif", "Presentation mode on") : tr("Mode presentasi", "Presentation mode")))
            .padding(.trailing, 6)

            TimelineView(.everyMinute) { context in
                Text(Fmt.clock(context.date))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            Button {
                state.openSettingsMenu?()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("Pengaturan", "Settings"))
            .padding(.leading, 6)

            if let percent = power.percent {
                HStack(spacing: 3) {
                    Image(systemName: power.symbol)
                        .font(.system(size: 12))
                    Text("\(percent)%")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(power.isCharging || power.onAC ? Color.green : Theme.secondary)
                .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: state.tab)
    }
}
