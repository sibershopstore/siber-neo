import AppKit
import SwiftUI

extension NSImage {
    /// Average image color, brightened and saturated, for the album artwork glow effect.
    /// Returns nil for artwork that is nearly black and white.
    func vividAverageColor() -> NSColor? {
        guard let image = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }

        let average = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation > 0.12 else { return nil }
        return NSColor(
            hue: hue,
            saturation: min(1, max(saturation * 1.35, 0.45)),
            brightness: max(brightness, 0.85),
            alpha: 1
        )
    }
}

/// Gradual appearance: fade, slight blur, and a subtle slide from the top.
final class AppearFlag: ObservableObject {
    @Published var visible = false
}

struct StaggeredAppear: ViewModifier {
    let delay: Double
    @StateObject var flag = AppearFlag()

    func body(content: Content) -> some View {
        content
            .opacity(flag.visible ? 1 : 0)
            .blur(radius: flag.visible ? 0 : 6)
            .offset(y: flag.visible ? 0 : -6)
            .onAppear {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86).delay(delay)) {
                    flag.visible = true
                }
            }
    }
}

struct SlideFade: ViewModifier {
    let offset: CGFloat
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
            .blur(radius: blur)
    }
}

extension View {
    func staggeredAppear(delay: Double) -> some View {
        modifier(StaggeredAppear(delay: delay))
    }
}

extension AnyTransition {
    /// Tab content slides gently in the direction of the tab change.
    static func tabSlide(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SlideFade(offset: forward ? 28 : -28, opacity: 0, blur: 4),
                identity: SlideFade(offset: 0, opacity: 1, blur: 0)
            ),
            removal: .modifier(
                active: SlideFade(offset: forward ? -18 : 18, opacity: 0, blur: 4),
                identity: SlideFade(offset: 0, opacity: 1, blur: 0)
            )
        )
    }

    /// Fade with blur, for closed-notch content.
    static var blurFade: AnyTransition {
        .modifier(
            active: SlideFade(offset: 0, opacity: 0, blur: 5),
            identity: SlideFade(offset: 0, opacity: 1, blur: 0)
        )
    }
}

struct CardFlip: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Album artwork flips like a card when the song changes.
    static var cardFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: CardFlip(angle: -90, opacity: 0), identity: CardFlip(angle: 0, opacity: 1)),
            removal: .modifier(active: CardFlip(angle: 90, opacity: 0), identity: CardFlip(angle: 0, opacity: 1))
        )
    }
}

/// Battery that fills slowly for the charging animation.
struct ChargingBatteryView: View {
    let level: Double
    @StateObject var flag = AppearFlag()

    var body: some View {
        let target = min(max(level, 0.04), 1)
        let start = max(target - 0.35, 0.04)
        let current = flag.visible ? target : start

        HStack(spacing: 7) {
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                        .frame(width: 30, height: 14)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.green)
                        .frame(width: 26 * CGFloat(current), height: 10)
                        .padding(.leading, 2)
                        .shadow(color: Theme.green.opacity(0.9), radius: 4)
                }
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 2, height: 5)
            }
            Text("\(Int((target * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.green)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.15)) {
                flag.visible = true
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id: Int
    let x: CGFloat
    let delay: Double
    let speed: CGFloat
    let drift: CGFloat
    let size: CGFloat
    let spin: Double
    let color: Color

    static func burst(count: Int = 48) -> [ConfettiParticle] {
        let palette: [Color] = [
            Theme.red, Theme.blue, Color(red: 1.0, green: 0.82, blue: 0.35),
            Color(red: 0.36, green: 0.86, blue: 0.56), Color(red: 1.0, green: 0.55, blue: 0.7), Color.white
        ]
        return (0..<count).map { index in
            ConfettiParticle(
                id: index,
                x: CGFloat.random(in: 0...1),
                delay: Double.random(in: 0...0.6),
                speed: CGFloat.random(in: 70...150),
                drift: CGFloat.random(in: -40...40),
                size: CGFloat.random(in: 4...7),
                spin: Double.random(in: -6...6),
                color: palette[index % palette.count]
            )
        }
    }
}

/// Confetti falling from the notch, drawn in the transparent area below it.
struct ConfettiLayer: View {
    let particles: [ConfettiParticle]
    let start: Date
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphics, size in
                let elapsed = context.date.timeIntervalSince(start)
                for particle in particles {
                    let t = elapsed - particle.delay
                    guard t > 0 else { continue }
                    let x = size.width / 2 + (particle.x - 0.5) * notchWidth * 1.4 + particle.drift * CGFloat(t)
                    let y = notchHeight + particle.speed * CGFloat(t) + 60 * CGFloat(t * t)
                    let opacity = max(0, min(1, 3.2 - t))
                    guard opacity > 0 else { continue }

                    var copy = graphics
                    copy.opacity = opacity
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(particle.spin * t))
                    let rect = CGRect(x: -particle.size / 2, y: -particle.size / 4, width: particle.size, height: particle.size / 2)
                    copy.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(particle.color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
