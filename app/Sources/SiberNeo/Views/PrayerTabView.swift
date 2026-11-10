import SwiftUI

struct PrayerTabView: View {
    @EnvironmentObject var prayer: PrayerService

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let upcoming = prayer.next(after: now)
            let zone = prayer.city.timeZone

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(text: tr("Berikutnya · \(prayer.city.name)", "Next · \(prayer.city.name)"))
                        if let upcoming {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(upcoming.name.title)
                                    .font(.system(size: 24, weight: .semibold))
                                Text(Fmt.clock(upcoming.date, timeZone: zone))
                                    .font(.system(size: 24, weight: .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.secondary)
                            }
                            Text(tr("dalam \(Fmt.countdown(upcoming.date.timeIntervalSince(now)))", "in \(Fmt.countdown(upcoming.date.timeIntervalSince(now)))"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.red)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Fmt.day(now))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                        Text(tr("Perhitungan Kemenag RI · lokal", "Kemenag RI method · on-device"))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(prayer.today) { time in
                        let isNext = time.date == upcoming?.date
                        let isPast = time.date <= now
                        VStack(spacing: 4) {
                            Text(time.name.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isNext ? Theme.red : Theme.tertiary)
                            Text(Fmt.clock(time.date, timeZone: zone))
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(isPast && !isNext ? Theme.tertiary : Color.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isNext ? Theme.red.opacity(0.14) : Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isNext ? Theme.red.opacity(0.5) : Theme.stroke)
                        )
                    }
                }

                HStack(spacing: 6) {
                    Button(prayer.remindersEnabled ? tr("Pengingat aktif", "Reminders on") : tr("Pengingat nonaktif", "Reminders off")) {
                        prayer.remindersEnabled.toggle()
                    }
                    .buttonStyle(ChipStyle(selected: prayer.remindersEnabled))

                    Button(tr("Jeda musik saat adzan", "Pause music at prayer time")) {
                        prayer.pauseMediaOnAdhan.toggle()
                    }
                    .buttonStyle(ChipStyle(selected: prayer.pauseMediaOnAdhan))

                    Spacer()

                    Menu {
                        ForEach(City.all, id: \.name) { city in
                            Button(city.name) { prayer.city = city }
                        }
                    } label: {
                        Text(tr("Ganti kota", "Change city"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}
