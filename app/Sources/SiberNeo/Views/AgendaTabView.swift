import AppKit
import SwiftUI

struct AgendaTabView: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        switch calendar.access {
        case .notDetermined:
            VStack(spacing: 12) {
                EmptyStateView(
                    icon: "calendar",
                    title: tr("Hubungkan Kalender", "Connect Calendar"),
                    subtitle: tr("Tampilkan agenda berikutnya dan gabung rapat langsung dari notch.", "See your next event and join meetings right from the notch.")
                )
                Button(tr("Izinkan akses Kalender", "Allow Calendar access")) { calendar.requestAccess() }
                    .buttonStyle(PillButtonStyle(primary: true))
            }
        case .denied:
            VStack(spacing: 12) {
                EmptyStateView(
                    icon: "calendar.badge.exclamationmark",
                    title: tr("Akses Kalender belum diizinkan", "Calendar access not allowed"),
                    subtitle: tr("Aktifkan melalui System Settings, Privacy & Security, Calendars.", "Turn it on in System Settings, Privacy & Security, Calendars.")
                )
                Button(tr("Buka pengaturan", "Open Settings")) { calendar.openPrivacySettings() }
                    .buttonStyle(PillButtonStyle())
            }
        case .granted:
            AgendaListView()
        }
    }
}

struct AgendaListView: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let upcoming = calendar.events.filter { $0.end > now }

            if let next = upcoming.first {
                HStack(alignment: .top, spacing: 16) {
                    NextEventCard(event: next, now: now)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if upcoming.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: tr("Selanjutnya", "Up next"))
                            ForEach(Array(upcoming.dropFirst().prefix(4))) { event in
                                EventRow(event: event)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: 240, alignment: .topLeading)
                    }
                }
            } else {
                EmptyStateView(
                    icon: "calendar",
                    title: tr("Tidak ada agenda", "No events"),
                    subtitle: tr("Tidak ada jadwal dalam 24 jam ke depan.", "Nothing scheduled in the next 24 hours.")
                )
            }
        }
    }
}

struct NextEventCard: View {
    let event: AgendaEvent
    let now: Date

    var body: some View {
        let ongoing = event.start <= now
        let countdown = ongoing
            ? tr("Berakhir dalam \(Fmt.countdown(event.end.timeIntervalSince(now)))", "Ends in \(Fmt.countdown(event.end.timeIntervalSince(now)))")
            : tr("Dimulai dalam \(Fmt.countdown(event.start.timeIntervalSince(now)))", "Starts in \(Fmt.countdown(event.start.timeIntervalSince(now)))")

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(event.color)
                    .frame(width: 4, height: 14)
                SectionLabel(text: ongoing ? tr("Sedang berlangsung", "Happening now") : tr("Agenda berikutnya", "Next event"))
            }

            Text(event.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(Fmt.clock(event.start)) – \(Fmt.clock(event.end))")
                    .monospacedDigit()
                if let location = event.location, !location.isEmpty, event.joinURL == nil {
                    Text("·")
                    Text(location).lineLimit(1)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)

            Text(countdown)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ongoing ? Theme.green : Theme.red)

            Spacer(minLength: 0)

            if let url = event.joinURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "video.fill")
                        Text(tr("Gabung rapat", "Join meeting"))
                    }
                }
                .buttonStyle(PillButtonStyle(primary: true))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
    }
}

struct EventRow: View {
    let event: AgendaEvent

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(Fmt.clock(event.start)) – \(Fmt.clock(event.end))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer(minLength: 4)
            if let url = event.joinURL {
                IconButton(systemName: "video.fill", size: 10, tint: Theme.secondary) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
    }
}
