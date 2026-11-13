import Foundation

setvbuf(stdout, nil, _IONBF, 0)
var failed = 0
func check(_ name: String, _ ok: Bool) {
    print(ok ? "✓" : "✗", name)
    if !ok { failed += 1 }
}

// разбор ответа Google
let sample = #"[[["Привет, мир. ","Hello world. ",null,null,10],["Это второе.\n\nТретье!","This is second.\n\nThird!",null,null,3]],null,"en",null]"#
let t = try! Translator.parse(Data(sample.utf8), target: "ru")
check("склейка сегментов", t.text == "Привет, мир. Это второе.\n\nТретье!")
check("язык оригинала", t.source == "en")
check("пустой ответ — ошибка", (try? Translator.parse(Data("[[],null,\"en\"]".utf8), target: "ru")) == nil)
check("мусор — ошибка", (try? Translator.parse(Data("<html>".utf8), target: "ru")) == nil)
// запасной адрес (clients5, dict-chrome-ex)
let d = try! Translator.parseDict(Data("[[\"Привет\\nмир\",\"en\"]]".utf8), target: "ru")
check("запасной: текст и язык", d.text == "Привет\nмир" && d.source == "en")
check("запасной: без языка", (try? Translator.parseDict(Data("[\"Hola\"]".utf8), target: "es"))?.text == "Hola")
check("запасной: страница Google «Sorry» — ошибка", (try? Translator.parseDict(Data("<html>Sorry</html>".utf8), target: "ru")) == nil)
check("запасной: пустой перевод — ошибка", (try? Translator.parseDict(Data("[[\"  \",\"en\"]]".utf8), target: "ru")) == nil)

// кодирование тела запроса
check("кириллица кодируется", Translator.formEncode("Привет & да=1+2") == "%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82%20%26%20%D0%B4%D0%B0%3D1%2B2")

// куда переводить
check("английский → русский", Translator.guessTarget("This is a menu-bar app for capture and markup", native: "ru", second: "en") == "ru")
check("русский → английский", Translator.guessTarget("Привет, как у тебя дела сегодня?", native: "ru", second: "en") == "en")
check("немецкий → русский", Translator.guessTarget("Ich habe heute keine Zeit für das Treffen", native: "ru", second: "en") == "ru")
check("украинский → русский", Translator.guessTarget("Привіт, як у тебе справи сьогодні?", native: "ru", second: "en") == "ru")
check("англ. пользователь: французский → английский", Translator.guessTarget("Je ne sais pas pourquoi il est parti", native: "en", second: "es") == "en")
check("русский с англицизмами → английский", Translator.guessTarget("твой софт безумно крутой, интересно работает ли он на API или просто код", native: "ru", second: "en") == "en")
check("русский с ошибками → английский", Translator.guessTarget("приветик, сделал прогу, зацени плиз", native: "ru", second: "en") == "en")
check("база кода языка", Lang.base("zh-CN") == "zh" && Lang.short("zh-CN") == "ZH")

// словарь названий
let none: [(String, [String])] = []
check("эпстор → App Store", Glossary.apply("Скачай это в эпсторе", user: none) == "Скачай это в App Store")
check("эпстор без падежа", Glossary.apply("эпстор", user: none) == "App Store")
check("Эпстор с большой", Glossary.apply("Эпстор лучше всех", user: none) == "App Store лучше всех")
check("айфон и макбук в падежах", Glossary.apply("на айфоне и макбуках", user: none) == "на iPhone и MacBook")
check("длинное раньше короткого", Glossary.apply("слушаю эпл мьюзик", user: none) == "слушаю Apple Music")
check("через пробел и слитно", Glossary.apply("ап стор и аппстор", user: none) == "App Store и App Store")
check("макароны не трогаем", Glossary.apply("макароны и макбук", user: none) == "макароны и MacBook")
check("Сирия — не Siri", Glossary.apply("Сирия и сири", user: none) == "Сирия и Siri")
check("гуглить не трогаем", Glossary.apply("надо погуглить в гугле", user: none) == "надо погуглить в Google")
check("стимул — не Steam", Glossary.apply("стимул купить в стиме", user: none) == "стимул купить в Steam")
check("маркдев → markdev", Glossary.apply("я маркдев, а это нотчстеш", user: none) == "я markdev, а это NotchStash")
let mine = Glossary.parse("# комментарий\nнотчстеш = NotchStash\n  маркдев=markdev  \nбез знака\n")
check("свой словарь читается", mine.count == 2 && mine[0].0 == "NotchStash" && mine[1].1 == ["маркдев"])
check("свой словарь с падежом", Glossary.apply("скачай нотчстеш от маркдева", user: mine) == "скачай NotchStash от markdev")

// живой запрос — только по OVERTEXT_LIVE=1
if ProcessInfo.processInfo.environment["OVERTEXT_LIVE"] == "1" {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let z = try await Translator.requestDict("I don't have time today, but tomorrow works.", target: "ru")
            print("  → запасной:", z.text, z.source)
            check("живой: запасной адрес", z.source == "en" && !z.text.isEmpty && Translator.isMostlyCyrillic(z.text))
            Translator.gtxPausedUntil = .distantPast
            let a = try await Translator.translate("Hi everyone, I'm the developer of this app, and it is free.", native: "ru", second: "en")
            print("  →", a.text, a.source, a.target)
            check("живой: en → ru", a.target == "ru" && a.text.contains("разработчик"))
            let b = try await Translator.translate("Я сделал бесплатную утилиту для Mac", native: "ru", second: "en")
            print("  →", b.text, b.source, b.target)
            check("живой: ru → en", b.target == "en" && b.text.lowercased().contains("mac"))
            let c = try await Translator.translate("Скачай это в эпсторе на айфоне", native: "ru", second: "en")
            print("  →", c.text)
            check("живой: эпстор → App Store", c.text.contains("App Store") && c.text.contains("iPhone"))
        } catch { check("живой запрос: \(error)", false) }
        sem.signal()
    }
    sem.wait()
}

print(failed == 0 ? "Все проверки пройдены" : "Провалено: \(failed)")
exit(failed == 0 ? 0 : 1)
