import Foundation
import NaturalLanguage

struct Translation: Equatable {
    let text: String
    let source: String
    let target: String
}

enum TranslateError: Error { case badResponse, empty }

/// Языки: «мой» (во что переводить чужой текст) и «второй» (во что переводить свой).
enum Lang {
    static let all: [(code: String, name: String)] = [
        ("ru", "Русский"), ("en", "English"), ("uk", "Українська"), ("de", "Deutsch"),
        ("fr", "Français"), ("es", "Español"), ("it", "Italiano"), ("pt", "Português"),
        ("pl", "Polski"), ("tr", "Türkçe"), ("zh-CN", "中文"), ("ja", "日本語"),
        ("ko", "한국어"), ("ar", "العربية"),
    ]

    static var isRussian: Bool {
        if let forced = ProcessInfo.processInfo.environment["OVERTEXT_LANG"] { return forced == "ru" }
        return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
    }

    static var systemNative: String {
        let sys = base(Locale.preferredLanguages.first ?? "en")
        return all.first { base($0.code) == sys }?.code ?? "en"
    }

    static var native: String {
        get { UserDefaults.standard.string(forKey: "native") ?? systemNative }
        set { UserDefaults.standard.set(newValue, forKey: "native") }
    }

    static var second: String {
        get { UserDefaults.standard.string(forKey: "second") ?? (base(native) == "en" ? "es" : "en") }
        set { UserDefaults.standard.set(newValue, forKey: "second") }
    }

    static func base(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }

    static func name(_ code: String) -> String { all.first { $0.code == code }?.name ?? code }
    static func short(_ code: String) -> String { base(code).uppercased() }
}

func L(_ ru: String, _ en: String) -> String { Lang.isRussian ? ru : en }

enum Translator {
    static let maxChars = 4800

    /// Чужой текст — на мой язык, мой текст — на второй.
    static func guessTarget(_ text: String, native: String = Lang.native, second: String = Lang.second) -> String {
        let r = NLLanguageRecognizer()
        r.processString(String(text.prefix(800)))
        var lang = r.dominantLanguage?.rawValue ?? ""
        // кириллица, которую определитель принял за болгарский/белорусский/сербский и т. п.,
        // для русского пользователя почти всегда русский с ошибками или англицизмами
        if Lang.base(native) == "ru", lang != "uk", isMostlyCyrillic(text) { lang = "ru" }
        return Lang.base(lang) == Lang.base(native) ? second : native
    }

    static func isMostlyCyrillic(_ s: String) -> Bool {
        var cyr = 0, lat = 0
        for u in s.unicodeScalars where CharacterSet.letters.contains(u) {
            if (0x0400...0x04FF).contains(u.value) { cyr += 1 } else if u.isASCII { lat += 1 }
        }
        return cyr > 0 && cyr >= lat * 2
    }

    static func translate(_ text: String, native: String = Lang.native, second: String = Lang.second) async throws -> Translation {
        let target = guessTarget(text, native: native, second: second)
        let text = Glossary.apply(text) // «эпстор» → App Store, до отправки в Google
        var t = try await request(text, target: target)
        // определитель ошибся и текст уже на этом языке — переводим в другую сторону
        if Lang.base(t.source) == Lang.base(target) {
            t = try await request(text, target: target == native ? second : native)
        }
        return t
    }

    /// Бесплатный адрес Google Translate. Текст уходит в теле запроса, не в адресе.
    static func request(_ text: String, target: String) async throws -> Translation {
        var c = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        c.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
        ]
        var req = URLRequest(url: c.url!, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(("q=" + formEncode(String(text.prefix(maxChars)))).utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw TranslateError.badResponse }
        return try parse(data, target: target)
    }

    /// Ответ: [[["перевод","оригинал",…],…], null, "en", …]
    static func parse(_ data: Data, target: String) throws -> Translation {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else { throw TranslateError.badResponse }
        var out = ""
        for s in segments {
            if let seg = s as? [Any], let piece = seg.first as? String { out += piece }
        }
        let source = (root.count > 2 ? root[2] as? String : nil) ?? "auto"
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslateError.empty }
        return Translation(text: trimmed, source: source, target: target)
    }

    static func formEncode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
