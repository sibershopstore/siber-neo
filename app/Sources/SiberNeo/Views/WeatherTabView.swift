import SwiftUI

struct WeatherTabView: View {
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        if let snapshot = weather.snapshot {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: tr("Cuaca · \(snapshot.city)", "Weather · \(snapshot.city)"))
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: WeatherCode.symbol(snapshot.code, isDay: snapshot.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 38))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Int(snapshot.temperature.rounded()))°")
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(WeatherCode.description(snapshot.code))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Label(tr("Terasa \(Int(snapshot.apparent.rounded()))°", "Feels \(Int(snapshot.apparent.rounded()))°"), systemImage: "thermometer.medium")
                        Label("\(snapshot.humidity)%", systemImage: "humidity.fill")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    Text(tr("Diperbarui \(Fmt.clock(snapshot.updated))", "Updated \(Fmt.clock(snapshot.updated))"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(width: 200, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(snapshot.hours) { hour in
                        WeatherHourColumn(hour: hour, timeZone: snapshot.timeZone)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
            }
        } else if weather.failed {
            VStack(spacing: 10) {
                EmptyStateView(icon: "cloud.slash", title: tr("Cuaca belum dapat dimuat", "Couldn't load weather"), subtitle: tr("Periksa koneksi internet, lalu coba lagi.", "Check your internet connection and try again."))
                Button(tr("Coba lagi", "Try again")) { weather.refresh() }
                    .buttonStyle(PillButtonStyle())
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct WeatherHourColumn: View {
    let hour: WeatherSnapshot.Hour
    let timeZone: TimeZone

    var body: some View {
        let localHour = Self.hourValue(hour.date, timeZone: timeZone)
        let isDay = (6..<18).contains(localHour)

        VStack(spacing: 6) {
            Text(String(format: "%02d", localHour))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.tertiary)
            Image(systemName: WeatherCode.symbol(hour.code, isDay: isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 15))
                .frame(height: 20)
            Text("\(Int(hour.temperature.rounded()))°")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            Text(hour.rainChance > 0 ? "\(hour.rainChance)%" : " ")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(hour.rainChance >= 60 ? Theme.blue : Theme.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    static func hourValue(_ date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}

/// Weather summary in the notch header; click to open details.
struct WeatherChip: View {
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var state: NotchState

    var body: some View {
        if let snapshot = weather.snapshot {
            Button {
                state.tab = .weather
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: WeatherCode.symbol(snapshot.code, isDay: snapshot.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Capsule().fill(state.tab == .weather ? Color.white.opacity(0.12) : Color.clear))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(Text(WeatherCode.description(snapshot.code)))
            .padding(.trailing, 4)
        }
    }
}
