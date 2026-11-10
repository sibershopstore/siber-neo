import Foundation

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case plain(String)
    case unavailable
}

/// Fetches lyrics from LRCLIB (lrclib.net). Only the song title, artist, and duration are sent.
final class LyricsService {
    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private var cache: [String: LyricsState] = [:]

    /// Called from the main thread; completion always returns on the main thread.
    func fetch(title: String, artist: String, duration: Double, tolerance: Double = 8, completion: @escaping (LyricsState) -> Void) {
        let key = "\(title)|\(artist)"
        if let cached = cache[key] {
            completion(cached)
            return
        }
        guard !title.isEmpty, var components = URLComponents(string: "https://lrclib.net/api/search") else {
            completion(.unavailable)
            return
        }
        var query = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            query.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components.queryItems = query
        guard let url = components.url else {
            completion(.unavailable)
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("SiberNeo/1.0 (https://neo.sibershopstore.com)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            var result: LyricsState = .unavailable
            if let data,
               (response as? HTTPURLResponse)?.statusCode == 200,
               let records = try? JSONDecoder().decode([Record].self, from: data) {
                result = Self.bestResult(from: records, duration: duration, tolerance: tolerance)
            }
            DispatchQueue.main.async {
                self.cache[key] = result
                completion(result)
            }
        }.resume()
    }

    private static func bestResult(from records: [Record], duration: Double, tolerance: Double) -> LyricsState {
        func distance(_ record: Record) -> Double {
            guard duration > 0, let d = record.duration else { return 9_999 }
            return abs(d - duration)
        }

        let synced = records
            .filter { !($0.syncedLyrics ?? "").isEmpty && (duration <= 0 || distance($0) < tolerance) }
            .sorted { distance($0) < distance($1) }
        if let best = synced.first, let text = best.syncedLyrics {
            let lines = parseLRC(text)
            if !lines.isEmpty { return .synced(lines) }
        }

        let plain = records
            .filter { !($0.plainLyrics ?? "").isEmpty }
            .sorted { distance($0) < distance($1) }
        if let best = plain.first, let text = best.plainLyrics {
            return .plain(text)
        }
        return .unavailable
    }

    static func parseLRC(_ source: String) -> [LyricLine] {
        var output: [LyricLine] = []
        for raw in source.components(separatedBy: .newlines) {
            var line = Substring(raw)
            var stamps: [Double] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                guard let time = parseStamp(tag) else { break }
                stamps.append(time)
                line = line[line.index(after: close)...]
            }
            let text = line.trimmingCharacters(in: .whitespaces)
            for time in stamps {
                output.append(LyricLine(time: time, text: text))
            }
        }
        return output.sorted { $0.time < $1.time }
    }

    private static func parseStamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}
