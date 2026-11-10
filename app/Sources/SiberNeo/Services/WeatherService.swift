import Foundation

struct WeatherSnapshot: Equatable {
    struct Hour: Equatable, Identifiable {
        let date: Date
        let temperature: Double
        let code: Int
        let rainChance: Int
        var id: Date { date }
    }

    let city: String
    let temperature: Double
    let apparent: Double
    let humidity: Int
    let code: Int
    let isDay: Bool
    let hours: [Hour]
    let timeZone: TimeZone
    let updated: Date
}

enum WeatherCode {
    static func isRain(_ code: Int) -> Bool {
        (51...67).contains(code) || (80...82).contains(code) || code >= 95
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61, 63, 66: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: return tr("Cerah", "Clear")
        case 1: return tr("Cerah berawan", "Mostly clear")
        case 2: return tr("Berawan sebagian", "Partly cloudy")
        case 3: return tr("Berawan", "Cloudy")
        case 45, 48: return tr("Berkabut", "Foggy")
        case 51...57: return tr("Gerimis", "Drizzle")
        case 61, 66: return tr("Hujan ringan", "Light rain")
        case 63: return tr("Hujan sedang", "Moderate rain")
        case 65, 67: return tr("Hujan lebat", "Heavy rain")
        case 71...77, 85, 86: return tr("Bersalju", "Snow")
        case 80, 81: return tr("Hujan lokal", "Rain showers")
        case 82: return tr("Hujan deras", "Heavy showers")
        case 95...99: return tr("Badai petir", "Thunderstorm")
        default: return tr("Berawan", "Cloudy")
        }
    }
}

/// Weather from Open-Meteo (free, no API key) based on the city selected for prayer times.
/// Refreshed every 20 minutes, with an alert when rain is likely within 1–2 hours.
final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var failed = false

    var onRainSoon: ((Int) -> Void)?

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let relative_humidity_2m: Double
            let weather_code: Int
            let is_day: Int
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let precipitation_probability: [Int?]
        }

        let utc_offset_seconds: Int
        let current: Current
        let hourly: Hourly
    }

    private var city: City?
    private var timer: Timer?
    private var lastRainAlert = Date.distantPast

    func start(city: City) {
        self.city = city
        refresh()
        let timer = Timer(timeInterval: 20 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func update(city: City) {
        guard city != self.city else { return }
        self.city = city
        snapshot = nil
        refresh()
    }

    func refresh() {
        guard let city, var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", city.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        guard let url = components.url else { return }

        let cityName = city.name
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("SiberNeo/1.0 (https://neo.sibershopstore.com)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                DispatchQueue.main.async { self?.failed = true }
                return
            }
            let snapshot = Self.makeSnapshot(decoded, city: cityName)
            DispatchQueue.main.async {
                guard let self, self.city?.name == cityName else { return }
                self.failed = false
                self.snapshot = snapshot
                self.checkRain(snapshot)
            }
        }.resume()
    }

    private static func makeSnapshot(_ response: Response, city: String) -> WeatherSnapshot {
        let timeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let hourly = response.hourly
        let count = min(hourly.time.count, hourly.temperature_2m.count, hourly.weather_code.count, hourly.precipitation_probability.count)
        let cutoff = Date().addingTimeInterval(-3600)
        var hours: [WeatherSnapshot.Hour] = []
        for index in 0..<count {
            guard let date = formatter.date(from: hourly.time[index]), date > cutoff else { continue }
            hours.append(WeatherSnapshot.Hour(
                date: date,
                temperature: hourly.temperature_2m[index],
                code: hourly.weather_code[index],
                rainChance: hourly.precipitation_probability[index] ?? 0
            ))
            if hours.count >= 9 { break }
        }

        let current = response.current
        return WeatherSnapshot(
            city: city,
            temperature: current.temperature_2m,
            apparent: current.apparent_temperature,
            humidity: Int(current.relative_humidity_2m.rounded()),
            code: current.weather_code,
            isDay: current.is_day == 1,
            hours: hours,
            timeZone: timeZone,
            updated: Date()
        )
    }

    private func checkRain(_ snapshot: WeatherSnapshot) {
        guard !WeatherCode.isRain(snapshot.code),
              Date().timeIntervalSince(lastRainAlert) > 3 * 3600 else { return }
        let soon = snapshot.hours.dropFirst().prefix(2)
        if let peak = soon.map({ $0.rainChance }).max(), peak >= 70 {
            lastRainAlert = Date()
            onRainSoon?(peak)
        }
    }
}
