import AppKit
import SwiftUI

struct NowPlaying: Equatable {
    enum Source: Equatable {
        case spotify, music, youtube, system
    }

    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var positionDate: Date
    var isPlaying: Bool
    var source: Source
    var artwork: NSImage?

    var trackKey: String { "\(title)|\(artist)" }

    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        let value = position + date.timeIntervalSince(positionDate)
        return duration > 0 ? min(value, duration) : value
    }
}

/// Combines playback information from Spotify, Apple Music, and system sources.
/// Spotify and Apple Music are read through distributed notifications (no polling),
/// and controlled through AppleScript.
final class MediaController: ObservableObject {
    static let spotifyID = "com.spotify.client"
    static let musicID = "com.apple.Music"

    @Published private(set) var track: NowPlaying?
    @Published private(set) var lyrics: LyricsState = .idle
    /// Dominant album artwork color for the glow effect, or nil.
    @Published private(set) var accent: NSColor?
    private weak var accentSource: NSImage?

    var accentColor: Color? {
        accent.map { Color(nsColor: $0) }
    }
    @Published var showLyrics = false {
        didSet {
            if showLyrics { loadLyricsIfNeeded() }
        }
    }

    private var appTrack: NowPlaying? {
        didSet { recompute() }
    }
    private var systemTrack: NowPlaying? {
        didSet { recompute() }
    }
    private var youtubeTrack: NowPlaying? {
        didSet { recompute() }
    }

    /// True when YouTube is open in a browser but "Allow JavaScript from Apple Events" is not enabled.
    @Published private(set) var youtubeBlocked = false

    private let youtube = YouTubeBridge()
    private var youtubeArtworkID: String?

    private let remote = MediaRemoteBridge()
    private let lyricsService = LyricsService()
    private var lyricsKey: String?
    private var spotifyArtworkID: String?
    private var musicArtworkKey: String?
    private var observers: [NSObjectProtocol] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleSpotify(note.userInfo)
        })
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleMusic(note.userInfo)
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.handleTermination(bundleID: app?.bundleIdentifier)
        })

        remote.onUpdate = { [weak self] info in
            self?.handleSystem(info)
        }
        remote.start()

        youtube.onUpdate = { [weak self] snapshot, _ in
            self?.handleYouTube(snapshot)
        }
        youtube.onBlockedChange = { [weak self] blocked in
            self?.youtubeBlocked = blocked
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.bootstrap()
        }
    }

    private var youtubeStarted = false

    /// Starts reading YouTube in the browser. Deferred until onboarding is complete because it triggers the Automation permission.
    func startYouTube() {
        guard !youtubeStarted else { return }
        youtubeStarted = true
        youtube.start()
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard let track else { return }
        switch track.source {
        case .spotify: AppleScript.run("tell application \"Spotify\" to playpause")
        case .music: AppleScript.run("tell application \"Music\" to playpause")
        case .youtube: youtube.togglePlayPause()
        case .system: remote.send(.togglePlayPause)
        }
    }

    func next() {
        guard let track else { return }
        switch track.source {
        case .spotify: AppleScript.run("tell application \"Spotify\" to next track")
        case .music: AppleScript.run("tell application \"Music\" to next track")
        case .youtube: youtube.next()
        case .system: remote.send(.next)
        }
    }

    func previous() {
        guard let track else { return }
        switch track.source {
        case .spotify: AppleScript.run("tell application \"Spotify\" to previous track")
        case .music: AppleScript.run("tell application \"Music\" to previous track")
        case .youtube: youtube.previous()
        case .system: remote.send(.previous)
        }
    }

    func pause() {
        guard let track, track.isPlaying else { return }
        switch track.source {
        case .spotify: AppleScript.run("tell application \"Spotify\" to pause")
        case .music: AppleScript.run("tell application \"Music\" to pause")
        case .youtube: youtube.pause()
        case .system: remote.send(.pause)
        }
    }

    func seek(to seconds: Double) {
        guard let track else { return }
        let value = String(format: "%.2f", max(seconds, 0))
        switch track.source {
        case .spotify:
            AppleScript.run("tell application \"Spotify\" to set player position to \(value)")
            appTrack?.position = seconds
            appTrack?.positionDate = Date()
        case .music:
            AppleScript.run("tell application \"Music\" to set player position to \(value)")
            appTrack?.position = seconds
            appTrack?.positionDate = Date()
        case .youtube:
            youtube.seek(to: seconds)
            youtubeTrack?.position = seconds
            youtubeTrack?.positionDate = Date()
        case .system:
            remote.seek(to: seconds)
            systemTrack?.position = seconds
            systemTrack?.positionDate = Date()
        }
    }

    // MARK: - Spotify

    private func handleSpotify(_ info: [AnyHashable: Any]?) {
        guard let info else { return }
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if appTrack?.source == .spotify { appTrack = nil }
            return
        }

        var track = NowPlaying(
            title: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000,
            position: (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0,
            positionDate: Date(),
            isPlaying: state == "Playing",
            source: .spotify,
            artwork: nil
        )
        if let previous = appTrack, previous.source == .spotify, previous.trackKey == track.trackKey {
            track.artwork = previous.artwork
        }
        appTrack = track

        if let trackID = info["Track ID"] as? String, trackID != spotifyArtworkID {
            spotifyArtworkID = trackID
            fetchSpotifyArtwork(trackID)
        }
    }

    /// Fetches album artwork through Spotify's official oEmbed endpoint, without AppleScript.
    private func fetchSpotifyArtwork(_ trackID: String) {
        let parts = trackID.split(separator: ":")
        guard parts.count == 3,
              var components = URLComponents(string: "https://open.spotify.com/oembed") else { return }
        components.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/\(parts[1])/\(parts[2])")]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumb = json["thumbnail_url"] as? String,
                  let imageURL = URL(string: thumb) else { return }
            URLSession.shared.dataTask(with: imageURL) { imageData, _, _ in
                guard let imageData, let image = NSImage(data: imageData) else { return }
                DispatchQueue.main.async {
                    guard let self, self.spotifyArtworkID == trackID, self.appTrack?.source == .spotify else { return }
                    self.appTrack?.artwork = image
                }
            }.resume()
        }.resume()
    }

    // MARK: - Apple Music

    private func handleMusic(_ info: [AnyHashable: Any]?) {
        guard let info else { return }
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if appTrack?.source == .music { appTrack = nil }
            return
        }

        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let key = "\(title)|\(artist)"
        let previous = appTrack?.source == .music ? appTrack : nil
        let samePrevious = previous?.trackKey == key

        let position = AppleScript.run("tell application \"Music\" to get player position")?.doubleValue
            ?? (samePrevious ? previous?.position ?? 0 : 0)

        var track = NowPlaying(
            title: title,
            artist: artist,
            album: info["Album"] as? String ?? "",
            duration: ((info["Total Time"] as? NSNumber)?.doubleValue ?? 0) / 1000,
            position: position,
            positionDate: Date(),
            isPlaying: state == "Playing",
            source: .music,
            artwork: samePrevious ? previous?.artwork : nil
        )

        if musicArtworkKey != key {
            musicArtworkKey = key
            if let data = AppleScript.run("tell application \"Music\" to get data of artwork 1 of current track")?.data {
                track.artwork = NSImage(data: data)
            }
        }
        appTrack = track
    }

    // MARK: - YouTube (browser)

    private func handleYouTube(_ snapshot: YouTubeBridge.Snapshot?) {
        guard let snapshot, !snapshot.title.isEmpty else {
            if youtubeTrack != nil { youtubeTrack = nil }
            return
        }

        let now = Date()
        var track = NowPlaying(
            title: snapshot.title,
            artist: snapshot.artist,
            album: "",
            duration: snapshot.duration,
            position: snapshot.position,
            positionDate: now,
            isPlaying: !snapshot.paused,
            source: .youtube,
            artwork: nil
        )

        if let previous = youtubeTrack, previous.trackKey == track.trackKey {
            track.artwork = previous.artwork
            let drift = abs(previous.position(at: now) - snapshot.position)
            if previous.isPlaying == track.isPlaying, drift < 1.5, abs(previous.duration - track.duration) < 1 {
                return
            }
        }
        youtubeTrack = track

        if snapshot.id != youtubeArtworkID {
            youtubeArtworkID = snapshot.id
            fetchYouTubeArtwork(snapshot.art, id: snapshot.id)
        }
    }

    private func fetchYouTubeArtwork(_ address: String, id: String) {
        guard let url = URL(string: address) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.youtubeArtworkID == id else { return }
                self.youtubeTrack?.artwork = image
            }
        }.resume()
    }

    // MARK: - System (MediaRemote)

    private func handleSystem(_ info: [String: Any]?) {
        guard let info,
              let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
              !title.isEmpty else {
            systemTrack = nil
            return
        }
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
        let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date()
        let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

        var artwork = artworkData.flatMap { NSImage(data: $0) }
        if artwork == nil, let previous = systemTrack, previous.trackKey == "\(title)|\(artist)" {
            artwork = previous.artwork
        }

        systemTrack = NowPlaying(
            title: title,
            artist: artist,
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0,
            position: elapsed,
            positionDate: timestamp,
            isPlaying: rate > 0,
            source: .system,
            artwork: artwork
        )
    }

    // MARK: - Lifecycle

    private func handleTermination(bundleID: String?) {
        guard let bundleID, let current = appTrack else { return }
        if (bundleID == Self.spotifyID && current.source == .spotify) ||
            (bundleID == Self.musicID && current.source == .music) {
            appTrack = nil
        }
    }

    /// Reads the initial state at launch, only if the player is already running,
    /// so AppleScript does not launch the app.
    private func bootstrap() {
        if AppleScript.isRunning(Self.spotifyID),
           let result = AppleScript.run("""
            tell application "Spotify"
                if player state is stopped then return {}
                return {name of current track, artist of current track, album of current track, duration of current track, player position, (player state as string), id of current track}
            end tell
            """), result.numberOfItems >= 7 {
            let info: [AnyHashable: Any] = [
                "Name": result.atIndex(1)?.stringValue ?? "",
                "Artist": result.atIndex(2)?.stringValue ?? "",
                "Album": result.atIndex(3)?.stringValue ?? "",
                "Duration": NSNumber(value: Double(result.atIndex(4)?.int32Value ?? 0)),
                "Playback Position": NSNumber(value: result.atIndex(5)?.doubleValue ?? 0),
                "Player State": result.atIndex(6)?.stringValue == "playing" ? "Playing" : "Paused",
                "Track ID": result.atIndex(7)?.stringValue ?? ""
            ]
            handleSpotify(info)
        }

        if appTrack == nil,
           AppleScript.isRunning(Self.musicID),
           let result = AppleScript.run("""
            tell application "Music"
                if player state is stopped then return {}
                return {name of current track, artist of current track, album of current track, duration of current track, (player state as string)}
            end tell
            """), result.numberOfItems >= 5 {
            let info: [AnyHashable: Any] = [
                "Name": result.atIndex(1)?.stringValue ?? "",
                "Artist": result.atIndex(2)?.stringValue ?? "",
                "Album": result.atIndex(3)?.stringValue ?? "",
                "Total Time": NSNumber(value: (result.atIndex(4)?.doubleValue ?? 0) * 1000),
                "Player State": result.atIndex(5)?.stringValue == "playing" ? "Playing" : "Paused"
            ]
            handleMusic(info)
        }
    }

    // MARK: - Selection & lyrics

    private func recompute() {
        let candidates = [appTrack, youtubeTrack, systemTrack].compactMap { $0 }
        let chosen = candidates.first(where: { $0.isPlaying }) ?? candidates.first
        if chosen != track {
            track = chosen
        }
        updateAccent()
        guard let chosen else {
            lyrics = .idle
            lyricsKey = nil
            return
        }
        if showLyrics, chosen.trackKey != lyricsKey {
            loadLyrics(for: chosen)
        }
    }

    private func updateAccent() {
        let image = track?.artwork
        guard image !== accentSource else { return }
        accentSource = image
        let color = image?.vividAverageColor()
        if color != accent {
            accent = color
        }
    }

    private func loadLyricsIfNeeded() {
        guard let track, track.trackKey != lyricsKey else { return }
        loadLyrics(for: track)
    }

    private func loadLyrics(for track: NowPlaying) {
        let key = track.trackKey
        lyricsKey = key
        lyrics = .loading
        let query = Self.lyricsQuery(for: track)
        lyricsService.fetch(
            title: query.title,
            artist: query.artist,
            duration: track.duration,
            tolerance: track.source == .youtube ? 25 : 8
        ) { [weak self] result in
            guard let self, self.lyricsKey == key else { return }
            self.lyrics = result
        }
    }

    /// YouTube video titles often look like "Artist - Song (Official Video)"; they are cleaned up to match LRCLIB.
    static func lyricsQuery(for track: NowPlaying) -> (title: String, artist: String) {
        guard track.source == .youtube else { return (track.title, track.artist) }

        var title = track.title
        let noise = [
            "\\(.*?\\)", "\\[.*?\\]", "【.*?】",
            "(?i)official\\s*(music\\s*)?video", "(?i)lyrics?\\s*video", "(?i)official\\s*audio",
            "(?i)\\bMV\\b", "(?i)\\bHD\\b", "(?i)\\b4K\\b"
        ]
        for pattern in noise {
            title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        var artist = track.artist
            .replacingOccurrences(of: " - Topic", with: "")
            .replacingOccurrences(of: "VEVO", with: "")

        let parts = title.components(separatedBy: " - ")
        if parts.count >= 2 {
            artist = parts[0]
            title = parts[1...].joined(separator: " - ")
        }

        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-|·"))
        return (title.trimmingCharacters(in: trimSet), artist.trimmingCharacters(in: trimSet))
    }
}
