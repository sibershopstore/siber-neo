import SwiftUI

extension HabitKind {
    var tint: Color {
        switch self {
        case .water: return Theme.blue
        case .coffee: return Color(red: 0.80, green: 0.56, blue: 0.36)
        case .snack: return Color(red: 1.0, green: 0.62, blue: 0.45)
        case .smoke: return Color(red: 0.62, green: 0.64, blue: 0.70)
        }
    }
}

final class HabitSelection: ObservableObject {
    @Published var kind: HabitKind = .water
}

struct HabitTabView: View {
    @StateObject var selection = HabitSelection()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HabitCard(kind: .water, selection: selection)
                    HabitCard(kind: .coffee, selection: selection)
                }
                HStack(spacing: 8) {
                    HabitCard(kind: .snack, selection: selection)
                    HabitCard(kind: .smoke, selection: selection)
                }
            }
            .frame(width: 400)

            HabitChart(kind: selection.kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct HabitCard: View {
    @EnvironmentObject var habits: HabitStore
    let kind: HabitKind
    @ObservedObject var selection: HabitSelection

    var body: some View {
        let count = habits.count(kind)
        let target = habits.target(for: kind)
        let isLimit = habits.isLimit(kind)
        let over = isLimit && target != nil && count > (target ?? 0)
        let reached = !isLimit && target != nil && count >= (target ?? 0)
        let selected = selection.kind == kind

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(kind.tint.opacity(0.16)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                    Text(target.map { "\(count) / \($0) \(kind.unit)" } ?? "\(count) \(kind.unit)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(over ? Theme.red : Color.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                IconButton(systemName: "minus", size: 9, tint: Theme.tertiary) {
                    habits.remove(kind)
                }

                Button {
                    habits.add(kind)
                    selection.kind = kind
                } label: {
                    Image(systemName: reached ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(over ? Theme.red : kind.tint))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let target {
                let fraction = min(Double(count) / Double(max(target, 1)), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(over ? Theme.red : (reached ? Theme.green : kind.tint))
                        .frame(width: 150 * CGFloat(fraction))
                }
                .frame(width: 150, height: 4)
                .animation(.easeOut(duration: 0.25), value: count)
            } else {
                Text(tr("Hari ini", "Today"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                    .frame(height: 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? kind.tint.opacity(0.7) : Theme.stroke, lineWidth: selected ? 1.2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selection.kind = kind }
    }
}

struct HabitChart: View {
    @EnvironmentObject var habits: HabitStore
    let kind: HabitKind

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Lang.locale
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        let history = habits.history(kind, days: 7)
        let target = habits.target(for: kind)
        let isLimit = habits.isLimit(kind)
        let peak = max(history.map { $0.count }.max() ?? 0, target ?? 0, 1)
        let total = history.reduce(0) { $0 + $1.count }
        let average = Double(total) / Double(max(history.count, 1))

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: tr("7 hari · \(kind.title)", "7 days · \(kind.title)"))
                Spacer()
                Text(tr("Rata-rata", "Average") + " " + String(format: "%.1f", average))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                MascotView(size: 26, interactive: true)
                    .frame(width: 34, height: 24)
            }

            GeometryReader { geo in
                let maxBar = max(geo.size.height - 30, 10)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(history.indices, id: \.self) { index in
                        let item = history[index]
                        let isToday = index == history.count - 1
                        let exceeded = isLimit && target != nil && item.count > (target ?? 0)
                        let met = !isLimit && target != nil && item.count >= (target ?? 0)

                        VStack(spacing: 3) {
                            Spacer(minLength: 0)
                            Text("\(item.count)")
                                .font(.system(size: 9, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.tertiary)
                                .opacity(item.count > 0 ? 1 : 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(exceeded ? Theme.red : kind.tint.opacity(met || isToday ? 1 : 0.5))
                                .frame(height: max(3, maxBar * CGFloat(item.count) / CGFloat(peak)))
                            Text(Self.dayFormatter.string(from: item.date))
                                .font(.system(size: 9, weight: isToday ? .semibold : .regular))
                                .foregroundStyle(isToday ? Color.white : Theme.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: total)
            }

            HabitSettingsRow(kind: kind)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
    }
}

struct HabitSettingsRow: View {
    @EnvironmentObject var habits: HabitStore
    let kind: HabitKind

    var body: some View {
        HStack(spacing: 10) {
            switch kind {
            case .water:
                optionMenu(
                    label: tr("Target \(habits.waterGoal) gelas", "Goal \(habits.waterGoal) glasses"),
                    options: [6, 8, 10, 12].map { (tr("\($0) gelas", "\($0) glasses"), $0) }
                ) { habits.waterGoal = $0 }
                optionMenu(
                    label: habits.waterInterval > 0 ? tr("Ingatkan tiap \(habits.waterInterval) mnt", "Remind every \(habits.waterInterval) min") : tr("Pengingat mati", "Reminders off"),
                    options: [(tr("Mati", "Off"), 0), (tr("30 menit", "30 minutes"), 30), (tr("45 menit", "45 minutes"), 45), (tr("60 menit", "60 minutes"), 60), (tr("90 menit", "90 minutes"), 90), (tr("120 menit", "120 minutes"), 120)]
                ) { habits.waterInterval = $0 }
            case .coffee:
                optionMenu(
                    label: habits.coffeeLimit > 0 ? tr("Batas \(habits.coffeeLimit) cangkir", "Limit \(habits.coffeeLimit) cups") : tr("Tanpa batas", "No limit"),
                    options: [(tr("Tanpa batas", "No limit"), 0), (tr("1 cangkir", "1 cup"), 1), (tr("2 cangkir", "2 cups"), 2), (tr("3 cangkir", "3 cups"), 3), (tr("4 cangkir", "4 cups"), 4), (tr("5 cangkir", "5 cups"), 5)]
                ) { habits.coffeeLimit = $0 }
            case .snack:
                Button(habits.snackReminders ? tr("Pengingat 10.00 & 15.00 aktif", "Reminders at 10:00 & 15:00") : tr("Pengingat camilan mati", "Snack reminders off")) {
                    habits.snackReminders.toggle()
                }
                .buttonStyle(ChipStyle(selected: habits.snackReminders))
            case .smoke:
                optionMenu(
                    label: habits.smokeLimit > 0 ? tr("Batas \(habits.smokeLimit) batang", "Limit \(habits.smokeLimit) cigarettes") : tr("Tanpa batas", "No limit"),
                    options: [(tr("Tanpa batas", "No limit"), 0), (tr("3 batang", "3 cigarettes"), 3), (tr("5 batang", "5 cigarettes"), 5), (tr("10 batang", "10 cigarettes"), 10), (tr("15 batang", "15 cigarettes"), 15), (tr("20 batang", "20 cigarettes"), 20)]
                ) { habits.smokeLimit = $0 }
            }
            Spacer(minLength: 0)
        }
    }

    private func optionMenu(label: String, options: [(String, Int)], select: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button(options[index].0) { select(options[index].1) }
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .foregroundStyle(Theme.secondary)
    }
}
