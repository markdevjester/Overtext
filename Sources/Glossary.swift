import Foundation

/// Названия, которые Google не узнаёт в русском написании: «эпстор» → App Store.
/// Подставляются до перевода, в любом падеже: «в эпсторе», «на айфоне».
enum Glossary {
    /// Настоящее название и его русские написания. Пробел в написании — «пробел или ничего».
    static let builtIn: [(String, [String])] = [
        ("App Store", ["эпстор", "эп стор", "эпп стор", "эппстор", "апстор", "ап стор", "аппстор", "апп стор", "эпл стор", "эппл стор"]),
        ("Apple Music", ["эпл мьюзик", "эппл мьюзик", "эпл мьюзек", "эппл мюзик", "эпл мюзик"]),
        ("Apple Watch", ["эпл вотч", "эппл вотч", "эпл воч", "эппл воч", "эпл ватч", "эппл ватч"]),
        ("Apple Pay", ["эпл пэй", "эппл пэй", "эпл пей", "эппл пей", "эпл пай", "эппл пай"]),
        ("Apple", ["эпл", "эппл"]),
        ("iPhone", ["айфон"]),
        ("iPad", ["айпад", "айпэд"]),
        ("iMac", ["аймак"]),
        ("MacBook", ["макбук"]),
        ("macOS", ["макось", "макос", "мак ос"]),
        ("iOS", ["иос", "айос", "ай ос"]),
        ("iCloud", ["айклауд"]),
        ("AirPods", ["эйрподс", "аирподс", "эирподс", "эйрподсы", "аирподсы"]),
        ("AirDrop", ["эйрдроп", "аирдроп"]),
        ("FaceTime", ["фейстайм", "фэйстайм"]),
        ("Siri", ["сири"]),
        ("Xcode", ["икскод", "экскод", "иксикод"]),
        ("TestFlight", ["тестфлайт", "тест флайт"]),
        ("Google Play", ["гугл плей", "гугл плэй", "плей маркет", "плеймаркет", "плей стор", "плейстор"]),
        ("Google", ["гугл"]),
        ("YouTube", ["ютуб", "ютьюб", "ютюб"]),
        ("Telegram", ["телеграм", "телеграмм"]),
        ("WhatsApp", ["вотсап", "ватсап", "вацап", "воцап", "вотсапп", "ватсапп"]),
        ("Instagram", ["инстаграм", "инстаграмм"]),
        ("TikTok", ["тикток", "тик ток"]),
        ("Facebook", ["фейсбук", "фэйсбук"]),
        ("Twitter", ["твиттер", "твитер"]),
        ("Reddit", ["реддит", "редит"]),
        ("Discord", ["дискорд"]),
        ("Spotify", ["спотифай"]),
        ("Netflix", ["нетфликс"]),
        ("GitHub", ["гитхаб", "гит хаб"]),
        ("ChatGPT", ["чатгпт", "чат гпт", "чат джипити", "чатджипити"]),
        ("Claude", ["клод"]),
        ("Figma", ["фигм"]),
        ("Notion", ["ноушн", "ноушен"]),
        ("Photoshop", ["фотошоп"]),
        ("Windows", ["виндовс", "винд"]),
        ("Microsoft", ["майкрософт", "микрософт"]),
        ("LinkedIn", ["линкедин", "линкедын"]),
        ("Pinterest", ["пинтерест"]),
        ("Skype", ["скайп"]),
        ("Viber", ["вайбер"]),
        ("Steam", ["стим"]),
        ("PlayStation", ["плейстейшн", "плэйстейшн", "плойк"]),
        ("Xbox", ["иксбокс"]),
        ("Safari", ["сафари"]),
        ("Swift", ["свифт"]),
        ("markdev", ["маркдев", "макрдев", "марк дев"]),
        ("NotchStash", ["нотчстеш", "нотчстэш", "нотч стеш"]),
    ]

    /// Падежные окончания и множественное число: эпстор-а, айфон-е, макбук-ами…
    static let endings = "(?:а|у|е|ом|ы|и|ов|ам|ами|ах|ой|ей|ю|я|ем|ям|ях|ями)?"

    /// Свой словарь: строки «написание = название». Лежит рядом с настройками.
    static var userFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Overtext", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.txt")
    }

    static let userTemplate = """
    # Мой словарь Overtext — названия и имена, которые нужно переводить по-своему.
    # Одна строка — одно правило: как пишу = как должно быть.
    # Падежи учитываются сами: «нотчстеш» сработает и для «в нотчстеше».
    #
    # нотчстеш = NotchStash
    # маркдев = markdev

    """

    static func userEntries() -> [(String, [String])] {
        guard let s = try? String(contentsOf: userFile, encoding: .utf8) else { return [] }
        return parse(s)
    }

    static func parse(_ s: String) -> [(String, [String])] {
        s.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { return nil }
            let from = line[..<eq].trimmingCharacters(in: .whitespaces)
            let to = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty, !to.isEmpty else { return nil }
            return (to, [from])
        }
    }

    /// Заменяет русские написания настоящими названиями. Свой словарь важнее встроенного.
    static func apply(_ text: String, user: [(String, [String])] = userEntries()) -> String {
        var out = text
        // длинные написания раньше коротких: «эпл мьюзик» раньше «эпл»
        let rules = (user + builtIn)
            .flatMap { name, spellings in spellings.map { (name, $0) } }
            .sorted { $0.1.count > $1.1.count }
        for (name, spelling) in rules {
            let words = spelling.lowercased().split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let stem = words.joined(separator: "[\\s-]*")
            // окончания — только русским словам на согласную («сири» не должно поймать «Сирия»)
            let declines = spelling.range(of: "\\p{Cyrillic}[^аеёиоуыэюяАЕЁИОУЫЭЮЯ\\s]$", options: .regularExpression) != nil
            let pattern = "(?<![\\p{L}\\p{N}])" + stem + (declines ? endings : "") + "(?![\\p{L}\\p{N}])"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: name))
        }
        return out
    }
}
