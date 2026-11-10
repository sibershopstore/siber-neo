import Foundation

/// App language: follows the primary macOS language (Indonesian or English),
/// or the manual choice from the "Bahasa / Language" menu.
enum Lang {
    enum Choice: String, CaseIterable {
        case auto, id, en
    }

    static var choice: Choice {
        Choice(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .auto
    }

    static let isIndonesian: Bool = {
        switch choice {
        case .id: return true
        case .en: return false
        case .auto: return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("id")
        }
    }()

    static var locale: Locale {
        Locale(identifier: isIndonesian ? "id_ID" : "en_US")
    }
}

/// Bilingual text: first argument in Indonesian, second in English.
func tr(_ indonesian: String, _ english: String) -> String {
    Lang.isIndonesian ? indonesian : english
}
