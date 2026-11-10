import SwiftUI

struct FocusTabView: View {
    @EnvironmentObject var focus: FocusTimer

    var body: some View {
        HStack(spacing: 34) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(focus.progress))
                    .stroke(
                        focus.phase == .focus ? Theme.red : Theme.blue,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: focus.progress)
                VStack(spacing: 2) {
                    Text(Fmt.mmss(focus.remaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(focus.phase.title)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel(text: tr("Sesi \(focus.sessionNumber) dari \(FocusTimer.sessionsPerCycle)", "Session \(focus.sessionNumber) of \(FocusTimer.sessionsPerCycle)"))
                    HStack(spacing: 6) {
                        ForEach(0..<FocusTimer.sessionsPerCycle, id: \.self) { index in
                            Capsule()
                                .fill(index < focus.completedFocus ? Theme.red : Color.white.opacity(0.12))
                                .frame(width: 28, height: 5)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(focus.isRunning ? tr("Jeda", "Pause") : tr("Mulai", "Start")) {
                        if focus.isRunning {
                            focus.pause()
                        } else {
                            focus.start()
                        }
                    }
                    .buttonStyle(PillButtonStyle(primary: true))

                    Button(tr("Lewati", "Skip")) { focus.skip() }
                        .buttonStyle(PillButtonStyle())

                    Button("Reset") { focus.reset() }
                        .buttonStyle(PillButtonStyle())
                }

                HStack(spacing: 6) {
                    Text(tr("Durasi fokus", "Focus length"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                    ForEach([25, 45, 50], id: \.self) { minutes in
                        Button(tr("\(minutes) mnt", "\(minutes) min")) { focus.focusMinutes = minutes }
                            .buttonStyle(ChipStyle(selected: focus.focusMinutes == minutes))
                    }
                }
                .disabled(focus.isRunning)
                .opacity(focus.isRunning ? 0.5 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
    }
}
