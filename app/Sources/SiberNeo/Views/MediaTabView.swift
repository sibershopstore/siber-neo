import SwiftUI

struct MediaTabView: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        if let track = media.track {
            HStack(alignment: .center, spacing: 22) {
                PlayerView(track: track)
                    .frame(width: media.showLyrics ? 270 : nil)
                if media.showLyrics {
                    LyricsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: media.showLyrics)
        } else {
            VStack(spacing: 10) {
                MascotView(size: 54, interactive: true)
                Text(tr("Tidak ada media yang diputar", "Nothing is playing"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Text(media.youtubeBlocked
                     ? tr("YouTube terdeteksi. Aktifkan View → Developer → Allow JavaScript from Apple Events di browser.", "YouTube detected. Turn on View → Developer → Allow JavaScript from Apple Events in your browser.")
                     : tr("Putar musik di Spotify, Apple Music, atau YouTube di Chrome.", "Play music in Spotify, Apple Music, or YouTube in Chrome."))
                    .font(.system(size: 11))
                    .foregroundStyle(media.youtubeBlocked ? Theme.amber : Theme.tertiary)
                    .multilineTextAlignment(.center)
                PaletteSwatches()
                    .padding(.top, 2)
                AccessoryPicker()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject var media: MediaController
    let track: NowPlaying

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ArtworkView(image: track.artwork, size: 96, radius: 14)
                    .id(track.trackKey)
                    .transition(.cardFlip)
            }
            .shadow(color: (media.accentColor ?? .black).opacity(0.45), radius: 12, y: 4)
            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: track.trackKey)

            VStack(alignment: .leading, spacing: 5) {
                Text(track.title.isEmpty ? tr("Tanpa judul", "Untitled") : track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)

                ProgressBar(track: track) { seconds in
                    media.seek(to: seconds)
                }
                .padding(.top, 4)

                HStack(spacing: 2) {
                    IconButton(systemName: "backward.fill", size: 13) { media.previous() }
                    IconButton(systemName: track.isPlaying ? "pause.fill" : "play.fill", size: 17) { media.togglePlayPause() }
                    IconButton(systemName: "forward.fill", size: 13) { media.next() }
                    Spacer(minLength: 0)
                    IconButton(
                        systemName: "quote.bubble",
                        size: 13,
                        tint: media.showLyrics ? Theme.red : Theme.secondary
                    ) {
                        media.showLyrics.toggle()
                    }
                    .help(tr("Lirik", "Lyrics"))
                }
            }
        }
    }
}

struct ProgressBar: View {
    @EnvironmentObject var media: MediaController
    let track: NowPlaying
    let onSeek: (Double) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !track.isPlaying)) { context in
            let position = track.position(at: context.date)
            let fraction = track.duration > 0 ? min(max(position / track.duration, 0), 1) : 0

            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 4)
                        Capsule()
                            .fill(media.accentColor ?? Theme.red)
                            .frame(width: geo.size.width * CGFloat(fraction), height: 4)
                            .shadow(color: (media.accentColor ?? Theme.red).opacity(0.6), radius: 4)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onEnded { value in
                            guard track.duration > 0, geo.size.width > 0 else { return }
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            onSeek(Double(ratio) * track.duration)
                        }
                    )
                }
                .frame(height: 10)

                HStack {
                    Text(Fmt.duration(position))
                    Spacer()
                    Text("-" + Fmt.duration(max(track.duration - position, 0)))
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

struct LyricsView: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        switch media.lyrics {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            EmptyStateView(icon: "text.quote", title: tr("Lirik belum tersedia", "Lyrics not available"), subtitle: tr("Lagu ini belum ada di pustaka LRCLIB.", "This song isn't in the LRCLIB library yet."))
        case .plain(let text):
            ScrollView(showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .synced(let lines):
            SyncedLyricsView(lines: lines)
        }
    }
}

struct SyncedLyricsView: View {
    @EnvironmentObject var media: MediaController
    let lines: [LyricLine]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !(media.track?.isPlaying ?? false))) { context in
            let position = media.track?.position(at: context.date) ?? 0
            let current = lines.lastIndex(where: { $0.time <= position + 0.25 }) ?? -1

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(lines.indices, id: \.self) { index in
                            let line = lines[index]
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: index == current ? 15 : 13, weight: index == current ? .semibold : .regular))
                                .foregroundStyle(index == current ? Color.white : Theme.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .id(index)
                                .onTapGesture {
                                    media.seek(to: line.time)
                                }
                        }
                    }
                    .padding(.vertical, 70)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.2),
                            .init(color: .black, location: 0.8),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: current) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(max(current, 0), anchor: .center)
                }
            }
        }
    }
}
