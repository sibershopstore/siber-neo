import SwiftUI

extension MascotPalette {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }

    var shell: (top: Color, bottom: Color) {
        switch self {
        case .navy: return (Self.rgb(0.16, 0.21, 0.40), Self.rgb(0.06, 0.08, 0.17))
        case .crimson: return (Self.rgb(0.52, 0.12, 0.17), Self.rgb(0.21, 0.04, 0.07))
        case .graphite: return (Self.rgb(0.28, 0.29, 0.32), Self.rgb(0.10, 0.10, 0.12))
        case .frost: return (Self.rgb(0.96, 0.97, 1.0), Self.rgb(0.74, 0.80, 0.92))
        case .violet: return (Self.rgb(0.35, 0.23, 0.60), Self.rgb(0.13, 0.08, 0.27))
        }
    }

    var pods: (top: Color, bottom: Color) {
        switch self {
        case .navy, .frost: return (Theme.blue, Self.rgb(0.12, 0.25, 0.62))
        case .crimson: return (Self.rgb(1.0, 0.62, 0.62), Self.rgb(0.80, 0.30, 0.34))
        case .graphite: return (Theme.red, Self.rgb(0.60, 0.10, 0.14))
        case .violet: return (Self.rgb(1.0, 0.60, 0.80), Self.rgb(0.78, 0.32, 0.58))
        }
    }

    var screen: (top: Color, bottom: Color) {
        switch self {
        case .navy: return (Self.rgb(0.88, 0.93, 1.0), Self.rgb(0.76, 0.84, 1.0))
        case .crimson: return (Self.rgb(1.0, 0.95, 0.95), Self.rgb(0.98, 0.84, 0.86))
        case .graphite: return (Self.rgb(0.94, 0.95, 0.97), Self.rgb(0.80, 0.82, 0.86))
        case .frost: return (Self.rgb(0.11, 0.14, 0.26), Self.rgb(0.05, 0.07, 0.15))
        case .violet: return (Self.rgb(0.96, 0.93, 1.0), Self.rgb(0.86, 0.80, 1.0))
        }
    }

    var ink: Color {
        switch self {
        case .navy: return Self.rgb(0.07, 0.09, 0.18)
        case .crimson: return Self.rgb(0.22, 0.05, 0.08)
        case .graphite: return Self.rgb(0.08, 0.08, 0.10)
        case .frost: return Self.rgb(0.80, 0.89, 1.0)
        case .violet: return Self.rgb(0.13, 0.07, 0.24)
        }
    }

    var glint: Color {
        self == .frost ? Self.rgb(0.25, 0.50, 1.0) : .white
    }

    var screenGlow: Color {
        switch self {
        case .crimson: return Theme.red
        case .violet: return Self.rgb(0.70, 0.45, 1.0)
        default: return Theme.blue
        }
    }
}

/// Neo, the Siber Neo mascot: a tiny robot with a screen for a face and small headphones.
struct MascotView: View {
    @EnvironmentObject var mascot: MascotController
    var size: CGFloat
    var dancing: Bool = false
    var interactive: Bool = false

    static let accentText = Color(red: 0.74, green: 0.86, blue: 1.0)
    static let cheek = Color(red: 1.0, green: 0.55, blue: 0.62)

    var body: some View {
        Group {
            if dancing || mascot.mood == .dizzy || mascot.activityMode != .none {
                TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    character(time: t)
                        .rotationEffect(.degrees(swayAngle(time: t)), anchor: .bottom)
                        .offset(y: bounceOffset(time: t))
                }
            } else {
                character(time: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            mascot.poke()
        }
        .onHover { hovering in
            if hovering {
                mascot.startPetting()
            } else {
                mascot.stopPetting()
            }
        }
        .allowsHitTesting(interactive)
    }

    private func swayAngle(time t: Double) -> Double {
        if mascot.mood == .dizzy { return sin(t * 9) * 7 }
        switch mascot.activityMode {
        case .stretching: return sin(t * 2.2) * 12
        case .working: return 0
        case .none: return dancing ? sin(t * 7) * 9 : 0
        }
    }

    private func bounceOffset(time t: Double) -> CGFloat {
        if mascot.mood == .dizzy { return 0 }
        switch mascot.activityMode {
        case .stretching: return -CGFloat(abs(sin(t * 2.2))) * size * 0.05
        case .working: return -CGFloat(abs(sin(t * 11))) * size * 0.015
        case .none: return dancing ? -CGFloat(abs(sin(t * 7))) * size * 0.08 : 0
        }
    }

    private func character(time: Double) -> some View {
        let width = size
        let height = size * 0.84
        let mood = mascot.mood
        let palette = mascot.palette

        return ZStack {
            if mascot.activityMode == .stretching {
                arms(width: width, height: height, palette: palette, time: time)
            }
            earPods(width: width, height: height, palette: palette)
            shell(width: width, height: height, palette: palette)
            if mascot.weatherOutfit == .scarf {
                scarf(width: width, height: height)
                    .transition(.opacity)
            }
            face(width: width, height: height, mood: mood, palette: palette, time: time)
            extras(width: width, height: height, mood: mood)
            headwear(width: width, height: height)
        }
        .frame(width: width * 1.12, height: height)
        .scaleEffect(
            x: mood == .eating ? 1.06 : (mascot.breathe ? 0.985 : 1.02),
            y: mood == .eating ? 1.05 : (mascot.breathe ? 1.03 : 0.98),
            anchor: .bottom
        )
        .animation(.easeInOut(duration: 1), value: mascot.breathe)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mood)
        .animation(.easeInOut(duration: 0.4), value: palette)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: mascot.accessory)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: mascot.weatherOutfit)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: mascot.activityMode)
        .phaseAnimator([0.0, 1.0, 0.0, 0.55, 0.0], trigger: mascot.hops) { content, phase in
            content.offset(y: -CGFloat(phase) * height * 0.24)
        } animation: { _ in
            .spring(response: 0.2, dampingFraction: 0.65)
        }
    }

    // MARK: - Parts

    private func earPods(width: CGFloat, height: CGFloat, palette: MascotPalette) -> some View {
        HStack(spacing: width * 0.86) {
            pod(width: width, height: height, palette: palette)
            pod(width: width, height: height, palette: palette)
        }
    }

    private func pod(width: CGFloat, height: CGFloat, palette: MascotPalette) -> some View {
        RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
            .fill(LinearGradient(colors: [palette.pods.top, palette.pods.bottom], startPoint: .top, endPoint: .bottom))
            .frame(width: width * 0.12, height: height * 0.38)
    }

    private func shell(width: CGFloat, height: CGFloat, palette: MascotPalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.42, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [palette.shell.top, palette.shell.bottom], startPoint: .top, endPoint: .bottom))
            .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: max(0.6, width * 0.02)))
            .frame(width: width, height: height)
    }

    private func face(width: CGFloat, height: CGFloat, mood: MascotController.Mood, palette: MascotPalette, time: Double) -> some View {
        let screenWidth = width * 0.76
        let screenHeight = height * 0.62
        let warm = mood == .happy || mood == .loved

        return ZStack {
            RoundedRectangle(cornerRadius: screenHeight * 0.42, style: .continuous)
                .fill(LinearGradient(colors: [palette.screen.top, palette.screen.bottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: palette.screenGlow.opacity(0.55), radius: width * 0.05)

            VStack(spacing: screenHeight * 0.06) {
                HStack(spacing: screenWidth * 0.26) {
                    eye(width: width, mood: mood, palette: palette, time: time)
                    eye(width: width, mood: mood, palette: palette, time: time)
                }
                .frame(height: height * 0.22)
                .overlay {
                    eyewear(width: width, screenWidth: screenWidth, mood: mood, palette: palette)
                }

                mouth(width: width, mood: mood, palette: palette)
            }
            .offset(x: mascot.look * screenWidth * 0.1, y: screenHeight * 0.04)
            .animation(.easeOut(duration: 0.3), value: mascot.look)

            HStack(spacing: screenWidth * 0.5) {
                Ellipse().fill(Self.cheek.opacity(warm ? 0.85 : 0.45))
                Ellipse().fill(Self.cheek.opacity(warm ? 0.85 : 0.45))
            }
            .frame(width: screenWidth * 0.86, height: screenHeight * 0.13)
            .offset(y: screenHeight * 0.18)
        }
        .frame(width: screenWidth, height: screenHeight)
        .offset(y: height * 0.04)
    }

    @ViewBuilder
    private func eye(width: CGFloat, mood: MascotController.Mood, palette: MascotPalette, time: Double) -> some View {
        let diameter = width * 0.16
        let line = max(1, width * 0.045)

        switch mood {
        case .happy, .loved:
            ArchShape(upward: true)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .frame(width: diameter, height: diameter * 0.55)
        case .asleep, .yawning:
            ArchShape(upward: false)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .frame(width: diameter, height: diameter * 0.45)
        case .dizzy:
            Image(systemName: "hurricane")
                .font(.system(size: diameter * 0.95, weight: .bold))
                .foregroundStyle(palette.ink)
                .rotationEffect(.degrees(time * 540))
                .frame(width: diameter, height: diameter)
        case .awake, .sleepy, .tired, .eating:
            let open: CGFloat = mascot.isBlinking ? 0.12 : (mood == .awake || mood == .eating ? 1 : 0.5)
            ZStack {
                Ellipse()
                    .fill(palette.ink)
                Circle()
                    .fill(palette.glint)
                    .frame(width: diameter * 0.38, height: diameter * 0.38)
                    .offset(x: diameter * 0.16, y: -diameter * 0.16)
                    .opacity(open > 0.3 ? 1 : 0)
                Circle()
                    .fill(palette.glint.opacity(0.75))
                    .frame(width: diameter * 0.17, height: diameter * 0.17)
                    .offset(x: -diameter * 0.18, y: diameter * 0.2)
                    .opacity(open > 0.6 ? 1 : 0)
            }
            .frame(width: diameter, height: diameter * 1.1 * open)
            .animation(.easeInOut(duration: 0.08), value: mascot.isBlinking)
        }
    }

    @ViewBuilder
    private func mouth(width: CGFloat, mood: MascotController.Mood, palette: MascotPalette) -> some View {
        let mouthWidth = width * 0.12
        let thin = max(0.8, width * 0.035)

        switch mood {
        case .happy:
            OpenMouthShape()
                .fill(palette.ink)
                .overlay(
                    Ellipse()
                        .fill(Self.cheek)
                        .frame(width: mouthWidth * 0.55, height: mouthWidth * 0.3)
                        .offset(y: mouthWidth * 0.2)
                )
                .frame(width: mouthWidth, height: mouthWidth * 0.75)
        case .eating:
            Ellipse()
                .fill(palette.ink)
                .overlay(
                    Ellipse()
                        .fill(Self.cheek)
                        .frame(width: mouthWidth * 0.8, height: mouthWidth * 0.4)
                        .offset(y: mouthWidth * 0.28)
                )
                .frame(width: mouthWidth * 1.35, height: mouthWidth * 1.1)
        case .yawning:
            Ellipse()
                .fill(palette.ink)
                .frame(width: mouthWidth * 0.75, height: mouthWidth * 0.95)
        case .loved:
            ArchShape(upward: false)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: thin, lineCap: .round))
                .frame(width: mouthWidth * 1.0, height: mouthWidth * 0.45)
        case .asleep:
            Circle()
                .stroke(palette.ink, lineWidth: max(0.8, width * 0.03))
                .frame(width: mouthWidth * 0.4, height: mouthWidth * 0.4)
        case .tired, .dizzy:
            WavyLineShape()
                .stroke(palette.ink, style: StrokeStyle(lineWidth: max(0.8, width * 0.03), lineCap: .round))
                .frame(width: mouthWidth * 0.9, height: mouthWidth * 0.25)
        case .awake, .sleepy:
            ArchShape(upward: false)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: thin, lineCap: .round))
                .frame(width: mouthWidth * 0.8, height: mouthWidth * 0.35)
        }
    }

    /// Extra details: a sweat drop when tired, a heart when petted, and the item being held.
    @ViewBuilder
    private func extras(width: CGFloat, height: CGFloat, mood: MascotController.Mood) -> some View {
        if mood == .tired {
            Image(systemName: "drop.fill")
                .font(.system(size: max(5, width * 0.13)))
                .foregroundStyle(Color(red: 0.55, green: 0.80, blue: 1.0))
                .offset(x: width * 0.36, y: -height * 0.3)
                .transition(.opacity)
        }
        if mood == .loved {
            Image(systemName: "heart.fill")
                .font(.system(size: max(5, width * 0.16)))
                .foregroundStyle(Self.cheek)
                .offset(x: width * 0.42, y: -height * (mascot.breathe ? 0.5 : 0.42))
                .animation(.easeInOut(duration: 1), value: mascot.breathe)
                .transition(.scale.combined(with: .opacity))
        }
        if mascot.activityMode == .working {
            Image(systemName: "laptopcomputer")
                .font(.system(size: max(8, width * 0.62)))
                .foregroundStyle(Color(white: 0.82))
                .offset(y: height * 0.44)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        if mascot.isBirthday, mascot.prop == nil, mascot.activityMode == .none {
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: max(7, width * 0.34)))
                .foregroundStyle(MascotView.cheek)
                .offset(x: width * 0.55, y: height * 0.2)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
        if mascot.weatherOutfit == .umbrella, mascot.prop == nil, !mascot.isBirthday, mascot.activityMode == .none {
            Image(systemName: "umbrella.fill")
                .font(.system(size: max(7, width * 0.42)))
                .foregroundStyle(Theme.red)
                .rotationEffect(.degrees(-14))
                .offset(x: width * 0.55, y: -height * 0.28)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
        if let prop = mascot.prop {
            Image(systemName: prop)
                .font(.system(size: max(6, width * 0.22)))
                .foregroundStyle(Self.propColor(prop))
                .rotationEffect(.degrees(-18))
                .offset(x: width * 0.5, y: height * 0.2)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    /// Sunglasses when sunny and hot, or collectible glasses.
    @ViewBuilder
    private func eyewear(width: CGFloat, screenWidth: CGFloat, mood: MascotController.Mood, palette: MascotPalette) -> some View {
        let diameter = width * 0.16
        let eyesVisible = mood == .awake || mood == .sleepy || mood == .tired || mood == .eating
        if mascot.weatherOutfit == .sunglasses, eyesVisible || mood == .happy || mood == .loved {
            HStack(spacing: screenWidth * 0.26 - diameter * 0.8) {
                RoundedRectangle(cornerRadius: diameter * 0.35, style: .continuous)
                    .fill(Color.black.opacity(0.9))
                    .frame(width: diameter * 1.8, height: diameter * 1.2)
                RoundedRectangle(cornerRadius: diameter * 0.35, style: .continuous)
                    .fill(Color.black.opacity(0.9))
                    .frame(width: diameter * 1.8, height: diameter * 1.2)
            }
            .overlay(
                Rectangle()
                    .fill(Color.black.opacity(0.9))
                    .frame(width: screenWidth * 0.2, height: max(0.6, diameter * 0.18))
            )
            .transition(.opacity)
        } else if mascot.accessory == .glasses {
            HStack(spacing: screenWidth * 0.26 - diameter * 0.6) {
                Circle()
                    .stroke(palette.ink, lineWidth: max(0.6, width * 0.025))
                    .frame(width: diameter * 1.6, height: diameter * 1.6)
                Circle()
                    .stroke(palette.ink, lineWidth: max(0.6, width * 0.025))
                    .frame(width: diameter * 1.6, height: diameter * 1.6)
            }
            .overlay(
                Rectangle()
                    .fill(palette.ink)
                    .frame(width: screenWidth * 0.12, height: max(0.6, width * 0.02))
            )
            .transition(.opacity)
        }
    }

    private func scarf(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.07, style: .continuous)
                .fill(LinearGradient(colors: [Theme.red, Color(red: 0.65, green: 0.12, blue: 0.16)], startPoint: .top, endPoint: .bottom))
                .frame(width: width * 0.86, height: height * 0.15)
            RoundedRectangle(cornerRadius: height * 0.04, style: .continuous)
                .fill(Color(red: 0.72, green: 0.14, blue: 0.18))
                .frame(width: width * 0.13, height: height * 0.26)
                .offset(x: width * 0.24, y: height * 0.14)
        }
        .offset(y: height * 0.44)
    }

    /// Small arms raised alternately while Neo stretches.
    private func arms(width: CGFloat, height: CGFloat, palette: MascotPalette, time: Double) -> some View {
        let swing = sin(time * 2.2) * 18
        return ZStack {
            Capsule()
                .fill(palette.pods.top)
                .frame(width: width * 0.1, height: height * 0.5)
                .rotationEffect(.degrees(-28 + swing), anchor: .bottom)
                .offset(x: -width * 0.6, y: -height * 0.28)
            Capsule()
                .fill(palette.pods.top)
                .frame(width: width * 0.1, height: height * 0.5)
                .rotationEffect(.degrees(28 + swing), anchor: .bottom)
                .offset(x: width * 0.6, y: -height * 0.28)
        }
    }

    /// Headwear: birthday hat first, then seasonal accessory, then collectible accessory.
    @ViewBuilder
    private func headwear(width: CGFloat, height: CGFloat) -> some View {
        if mascot.isBirthday {
            partyHat(width: width, height: height)
        } else if let seasonal = mascot.seasonal {
            switch seasonal {
            case .peci:
                ZStack {
                    RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                        .fill(Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: max(0.5, width * 0.012))
                        )
                        .frame(width: width * 0.6, height: height * 0.24)
                    Rectangle()
                        .fill(Color(red: 0.86, green: 0.70, blue: 0.32))
                        .frame(width: width * 0.6, height: max(0.6, height * 0.025))
                        .offset(y: height * 0.07)
                }
                .offset(y: -height * 0.56)
            case .party:
                partyHat(width: width, height: height)
            case .merahPutih:
                VStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.86, green: 0.1, blue: 0.14))
                    Rectangle().fill(Color.white)
                }
                .frame(width: width * 0.9, height: height * 0.14)
                .clipShape(Capsule())
                .offset(y: -height * 0.3)
            }
        } else if let accessory = mascot.accessory {
            switch accessory {
            case .glasses:
                EmptyView()
            case .flower:
                Image(systemName: "camera.macro")
                    .font(.system(size: max(6, width * 0.24), weight: .semibold))
                    .foregroundStyle(MascotView.cheek)
                    .offset(x: width * 0.32, y: -height * 0.48)
            case .graduation:
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: max(7, width * 0.48)))
                    .foregroundStyle(Color(white: 0.28))
                    .offset(y: -height * 0.6)
            case .crown:
                Image(systemName: "crown.fill")
                    .font(.system(size: max(7, width * 0.4)))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 0.9, green: 0.62, blue: 0.2)], startPoint: .top, endPoint: .bottom))
                    .offset(y: -height * 0.58)
            }
        }
    }

    private func partyHat(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            PartyHatShape()
                .fill(LinearGradient(colors: [Theme.red, Color(red: 1.0, green: 0.78, blue: 0.3)], startPoint: .bottom, endPoint: .top))
                .frame(width: width * 0.32, height: height * 0.42)
            Circle()
                .fill(Color.white)
                .frame(width: width * 0.09, height: width * 0.09)
                .offset(y: -width * 0.04)
        }
        .rotationEffect(.degrees(14))
        .offset(x: width * 0.14, y: -height * 0.66)
    }

    private static func propColor(_ symbol: String) -> Color {
        if symbol.hasPrefix("drop") { return Color(red: 0.45, green: 0.72, blue: 1.0) }
        if symbol.hasPrefix("cup") { return Color(red: 0.85, green: 0.62, blue: 0.40) }
        return Color(red: 1.0, green: 0.66, blue: 0.45)
    }
}

/// A simple arc: upward for happy "^" eyes, downward for a smile and sleeping eyes.
struct ArchShape: Shape {
    var upward: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if upward {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.9)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.9)
            )
        }
        return path
    }
}

/// Cone-shaped party hat.
struct PartyHatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}

/// Open semicircle mouth when Neo is excited.
struct OpenMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.9)
        )
        path.closeSubpath()
        return path
    }
}

/// Wavy mouth when Neo is tired.
struct WavyLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / 3
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for index in 0..<3 {
            let startX = rect.minX + step * CGFloat(index)
            path.addQuadCurve(
                to: CGPoint(x: startX + step, y: rect.midY),
                control: CGPoint(x: startX + step / 2, y: index % 2 == 0 ? rect.minY : rect.maxY)
            )
        }
        return path
    }
}

/// Sleep indicator "z z z" that drifts up and down slowly.
struct SleepingZView: View {
    @EnvironmentObject var mascot: MascotController

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            Text("z").font(.system(size: 7, weight: .bold))
            Text("z").font(.system(size: 9, weight: .bold))
                .offset(y: mascot.breathe ? -3 : -1)
            Text("z").font(.system(size: 11, weight: .bold))
                .offset(y: mascot.breathe ? -6 : -3)
        }
        .foregroundStyle(MascotView.accentText.opacity(0.8))
        .animation(.easeInOut(duration: 1), value: mascot.breathe)
    }
}

/// Neo color options that can be clicked directly from the notch.
struct PaletteSwatches: View {
    @EnvironmentObject var mascot: MascotController

    var body: some View {
        HStack(spacing: 7) {
            ForEach(MascotPalette.allCases, id: \.self) { palette in
                let selected = mascot.palette == palette
                Button {
                    mascot.palette = palette
                    mascot.poke()
                } label: {
                    Circle()
                        .fill(LinearGradient(colors: [palette.shell.top, palette.shell.bottom], startPoint: .top, endPoint: .bottom))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(
                                selected ? Color.white : Color.white.opacity(0.22),
                                lineWidth: selected ? 1.6 : 0.8
                            )
                        )
                        .padding(2)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(palette.title)
            }
        }
    }
}


/// Neo's accessory collection: unlocked through achievements, click to wear or remove.
struct AccessoryPicker: View {
    @EnvironmentObject var achievements: AchievementStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NeoAccessory.allCases, id: \.self) { accessory in
                let unlocked = achievements.isUnlocked(accessory)
                let selected = achievements.equipped == accessory
                Button {
                    if unlocked {
                        achievements.equipped = selected ? nil : accessory
                    }
                } label: {
                    Image(systemName: unlocked ? accessory.symbol : "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? Theme.red : (unlocked ? Theme.secondary : Theme.tertiary.opacity(0.6)))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(selected ? Theme.red.opacity(0.16) : Color.white.opacity(0.05)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(unlocked ? accessory.title : achievements.requirementText(accessory))
            }
        }
    }
}
