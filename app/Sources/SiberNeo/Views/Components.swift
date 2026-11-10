import SwiftUI

enum Theme {
    static let red = Color(red: 0.90, green: 0.22, blue: 0.25)
    static let blue = Color(red: 0.25, green: 0.47, blue: 0.96)
    static let card = Color(red: 0.055, green: 0.07, blue: 0.11)
    static let stroke = Color.white.opacity(0.06)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.34)
    static let green = Color(red: 0.30, green: 0.84, blue: 0.52)
    static let amber = Color(red: 1.0, green: 0.64, blue: 0.22)
}

/// Notch shape: top corners curve outward to follow the bezel, bottom corners are rounded.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, rect.height / 2, (rect.width - 2 * top) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct PillButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(primary ? Color.white : Color.white.opacity(0.85))
            .background(Capsule().fill(primary ? Theme.red : Color.white.opacity(0.08)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct ChipStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? Theme.red : Theme.secondary)
            .background(Capsule().fill(selected ? Theme.red.opacity(0.16) : Color.white.opacity(0.05)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 14
    var tint: Color = .white
    let action: () -> Void

    @StateObject var flags = ViewFlags()

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size + 18, height: size + 18)
                .background(Circle().fill(Color.white.opacity(flags.hovering ? 0.10 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { flags.hovering = $0 }
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.tertiary)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    var size: CGFloat = 80
    var radius: CGFloat = 12

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.card, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct EqualizerView: View {
    var playing: Bool
    var color: Color = Theme.red

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let wave = abs(sin(t * (2.2 + Double(index) * 0.7) + Double(index)))
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: playing ? CGFloat(4 + 9 * wave) : 3)
                }
            }
            .frame(height: 14)
            .animation(.easeInOut(duration: 0.12), value: t)
        }
    }
}

/// Small view state (hover, copy) based on ObservableObject to avoid depending
/// on the @State macro, which requires a full Xcode installation.
final class ViewFlags: ObservableObject {
    @Published var hovering = false
    @Published var copied = false
}

final class TodoDraft: ObservableObject {
    @Published var text = ""
    @Published var useReminder = false
    @Published var reminderTime = Date().addingTimeInterval(3600)
}
