import Foundation

/// The app's interface language. The Portuguese text in the code is the key; English and Spanish
/// come from the tables in this folder. "auto" follows the Mac's language list.
enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, pt, en, es
    var id: String { rawValue }

    static let key = "app.language"

    /// Native names, so anyone can find their own language in the list.
    var label: String {
        switch self {
        case .auto: return L("Automático (idioma do Mac)")
        case .pt: return "Português"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    static var chosen: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "auto") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key); _current = nil }
    }

    /// The language in use: the choice, or the first of the Mac's languages we have (English otherwise).
    static var current: AppLanguage {
        if let c = _current { return c }
        var r: AppLanguage = .en
        if chosen != .auto {
            r = chosen
        } else {
            for l in Locale.preferredLanguages {
                let code = l.prefix(2).lowercased()
                if let m = AppLanguage(rawValue: code), m != .auto { r = m; break }
            }
        }
        _current = r
        return r
    }
    nonisolated(unsafe) private static var _current: AppLanguage?

    /// BCP-47 tag for speech recognition and the AI ("pt-BR", "en-US", "es-ES").
    var localeTag: String {
        switch self {
        case .en: return "en-US"
        case .es: return "es-ES"
        default: return "pt-BR"
        }
    }
}

/// Every translation table, keyed by the Portuguese text: [english, spanish].
/// Each part of the app keeps its own table in this folder.
private let tables: [[String: [String]]] = [l10nSettings, l10nTools]

private let merged: [String: [String]] = {
    var all: [String: [String]] = [:]
    for t in tables { all.merge(t) { a, _ in a } }
    return all
}()

/// Translates Portuguese UI text into the current language; with arguments, fills `%@`/`%d` like
/// String(format:). Text with no translation is shown in Portuguese.
func L(_ pt: String, _ args: CVarArg...) -> String {
    var s = pt
    switch AppLanguage.current {
    case .en: s = merged[pt]?[0] ?? pt
    case .es: s = merged[pt]?[1] ?? pt
    default: break
    }
    return args.isEmpty ? s : String(format: s, arguments: args)
}
