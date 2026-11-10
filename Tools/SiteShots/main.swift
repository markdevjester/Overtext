// Картинки для README на настоящих сайтах — без показа окон и без захвата экрана.
// Страница грузится в невидимый WebKit, перевод берётся у Google, поверх кладётся та же карточка,
// что рисует приложение.
//
//   swiftc -swift-version 5 Tools/SiteShots/main.swift Sources/Overlay.swift Sources/Translator.swift \
//     Sources/Glossary.swift Sources/Selection.swift -o /tmp/siteshots && /tmp/siteshots previews
import AppKit
import SwiftUI
import WebKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "previews"
let pageSize = CGSize(width: 1240, height: 760)

// MARK: - невидимый браузер

@MainActor
final class Browser: NSObject, WKNavigationDelegate {
    let window: NSWindow
    let web: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    override init() {
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: CGRect(origin: .zero, size: pageSize), configuration: cfg)
        web.appearance = NSAppearance(named: .aqua)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        // окно далеко за экраном и никогда не становится активным
        window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: pageSize.width, height: pageSize.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        window.isReleasedWhenClosed = false
        super.init()
        web.navigationDelegate = self
        window.orderBack(nil)
    }

    func load(_ url: String) async {
        await withCheckedContinuation { c in
            loaded = c
            web.load(URLRequest(url: URL(string: url)!))
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000) // шрифты и картинки
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in loaded?.resume(); loaded = nil }
    }

    func js(_ code: String) async -> Any? {
        try? await web.evaluateJavaScript(code)
    }

    func snapshot() async -> NSImage {
        await withCheckedContinuation { c in
            web.takeSnapshot(with: WKSnapshotConfiguration()) { img, _ in c.resume(returning: img ?? NSImage()) }
        }
    }
}

// MARK: - оформление

struct Wallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.14, green: 0.33, blue: 0.52),
                                Color(red: 0.42, green: 0.36, blue: 0.70),
                                Color(red: 0.93, green: 0.62, blue: 0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Окно браузера: светлая панель с кнопками и адресом, под ней страница.
struct BrowserWindow<Content: View>: View {
    let host: String
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                             Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { c in
                        Circle().fill(c).frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                .padding(.leading, 18)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                    Text(host).font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.black.opacity(0.62))
                .frame(width: 420, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.055)))
            }
            .frame(height: 52)
            .background(Color(white: 0.965))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5) }
            content
                .frame(width: width, height: height - 52, alignment: .topLeading)
                .clipped()
        }
        .frame(width: width, height: height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 22)
    }
}

/// Подпись-«таблетка» над окном.
struct Caption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.28)))
    }
}

@MainActor
func save<V: View>(_ name: String, _ size: CGSize, _ view: V) {
    let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
    r.scale = 1.25
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
        print("не получилось:", name); return
    }
    try? jpg.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name + ".jpg"))
    print("готово:", name, Int(size.width * 1.25), "×", Int(size.height * 1.25))
}

/// Модель карточки как в приложении, высота — как у настоящей подгонки.
@MainActor
func card(_ t: Translation, fontSize: CGFloat, width: CGFloat, minHeight: CGFloat) -> (OverlayModel, CGFloat) {
    let m = OverlayModel()
    m.staticRender = true
    m.shown = true
    m.style = .inPlace
    m.fontSize = fontSize
    m.phase = .done(t)
    let probe = NSHostingController(rootView: CardContent(m: m, measuring: true)
        .frame(width: width).fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .light))
    let h = ceil(probe.sizeThatFits(in: CGSize(width: width, height: 10_000)).height)
    return (m, max(h, minHeight))
}

let hideNoise = """
for (const s of ['#siteNotice', '#centralNotice', '.cn-fundraising', '.mw-dismissable-notice', '.vector-sticky-header'])
  document.querySelectorAll(s).forEach(e => e.style.display = 'none');
"""

// MARK: - сцены

@MainActor
func readingScene(_ b: Browser) async {
    await b.load("https://de.wikipedia.org/wiki/Buchdruck")
    _ = await b.js(hideNoise)
    let r = await b.js("""
    (() => { try {
      // абзац во всю ширину (не рядом с картинкой), 3–6 строк
      const all = [...document.querySelectorAll('#mw-content-text p')];
      const fits = p => {
        const r = document.createRange(); r.selectNodeContents(p);
        const ls = [...r.getClientRects()].filter(l => l.width > 4);
        const lines = new Set(ls.map(l => Math.round(l.top))).size;
        const right = Math.max(...ls.map(l => l.right));
        return lines >= 3 && lines <= 6 && right > p.getBoundingClientRect().right - 40;
      };
      const p = all.slice(1).find(p => p.innerText.trim().length > 300 && fits(p));
      window.scrollTo(0, p.getBoundingClientRect().top + window.scrollY - 160);
      const span = document.createElement('span');
      span.style.background = '#b4d7ff';
      while (p.firstChild) span.appendChild(p.firstChild);
      p.appendChild(span);
      const pr = p.getBoundingClientRect();
      const lines = [...span.getClientRects()];
      const top = Math.min(...lines.map(l => l.top)), bottom = Math.max(...lines.map(l => l.bottom));
      return [pr.left, top, pr.width, bottom - top, parseFloat(getComputedStyle(p).fontSize),
              p.innerText.replace(/\\[\\d+\\]/g, '').trim()];
    } catch (e) { return ['error', String(e), document.title, document.querySelectorAll('p').length]; } })()
    """) as? [Any] ?? []
    guard r.count == 6, let x = r[0] as? Double, let y = r[1] as? Double, let w = r[2] as? Double,
          let h = r[3] as? Double, let fs = r[4] as? Double, let text = r[5] as? String else {
        print("чтение: страница не разобралась", r); return
    }
    try? await Task.sleep(nanoseconds: 2_500_000_000) // картинки на странице догружаются после прокрутки
    let page = await b.snapshot()
    guard let t = try? await Translator.request(text, target: "en") else { print("чтение: нет перевода"); return }
    print("чтение:", text.prefix(60), "→", t.text.prefix(60))

    let cw = w + 2 * Metrics.padH
    let (m, ch) = card(t, fontSize: fs, width: cw, minHeight: h + 2 * Metrics.padV)
    let win = CGSize(width: pageSize.width, height: 52 + 600)
    save("page", CGSize(width: 1440, height: 800), ZStack(alignment: .topLeading) {
        Wallpaper()
        VStack(spacing: 22) {
            Caption(text: "Select text on any page, press ⌘E — it's translated right in place")
            BrowserWindow(host: "de.wikipedia.org", width: win.width, height: win.height) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: page).resizable().frame(width: pageSize.width, height: pageSize.height)
                    OverlayView(m: m) {}
                        .frame(width: cw, height: ch)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                        .offset(x: x - Metrics.padH, y: y - Metrics.padV)
                }
            }
        }
        .padding(.top, 34)
        .frame(maxWidth: .infinity)
    })
}

@MainActor
func fieldScene(_ b: Browser) async {
    let english = "history of the printing press in Germany"
    guard let t = try? await Translator.request(english, target: "es") else { print("поле: нет перевода"); return }
    print("поле:", english, "→", t.text)
    await b.load("https://es.wikipedia.org/wiki/Imprenta")
    _ = await b.js(hideNoise)

    func fill(_ value: String) async -> [Double] {
        let r = await b.js("""
        (() => {
          const i = [...document.querySelectorAll('input[name=search]')].find(e => e.offsetParent !== null);
          i.value = \(String(reflecting: value));
          const cs = getComputedStyle(i);
          const c = document.createElement('canvas').getContext('2d');
          c.font = cs.font;
          const ir = i.getBoundingClientRect();
          const left = ir.left + parseFloat(cs.paddingLeft) + parseFloat(cs.borderLeftWidth);
          const tw = c.measureText(i.value).width;
          return [ir.left, ir.top, ir.width, ir.height, left, tw, parseFloat(cs.fontSize)];
        })()
        """) as? [Double] ?? []
        return r
    }
    let before = await fill(english)
    let shotBefore = await b.snapshot()
    let after = await fill(t.text)
    let shotAfter = await b.snapshot()
    guard before.count == 7, after.count == 7 else { print("поле: нет строки поиска"); return }

    // полоса страницы вокруг строки поиска
    let bandTop = max(0, before[1] - 30), bandH: CGFloat = 112
    func band(_ img: NSImage, _ g: [Double], selected: Bool, caret: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: img).resizable().frame(width: pageSize.width, height: pageSize.height)
                .offset(y: -bandTop)
            if selected {
                Rectangle().fill(Color(red: 0.70, green: 0.84, blue: 1.0))
                    .frame(width: g[5] + 2, height: g[6] * 1.35)
                    .offset(x: g[4] - 1, y: g[1] + (g[3] - g[6] * 1.35) / 2 - bandTop)
                    .blendMode(.multiply)
            }
            if caret {
                Rectangle().fill(Color.black.opacity(0.85))
                    .frame(width: 1.5, height: g[6] * 1.3)
                    .offset(x: g[4] + g[5] + 1, y: g[1] + (g[3] - g[6] * 1.3) / 2 - bandTop)
            }
        }
        .frame(width: pageSize.width, height: bandH, alignment: .topLeading)
        .clipped()
    }
    save("field", CGSize(width: 1440, height: 560), ZStack(alignment: .topLeading) {
        Wallpaper()
        VStack(spacing: 18) {
            Caption(text: "Write in your language, select it, press ⌘E")
            BrowserWindow(host: "es.wikipedia.org", width: pageSize.width, height: 52 + bandH) {
                band(shotBefore, before, selected: true, caret: false)
            }
            Caption(text: "…and the field already says it in Spanish")
                .padding(.top, 14)
            BrowserWindow(host: "es.wikipedia.org", width: pageSize.width, height: 52 + bandH) {
                band(shotAfter, after, selected: false, caret: true)
            }
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    })
}

@MainActor
func notchScene() async {
    let german = "Der Buchdruck veränderte die Verbreitung von Wissen in Europa grundlegend."
    guard let t = try? await Translator.request(german, target: "en") else { print("чёлка: нет перевода"); return }
    print("чёлка:", t.text)
    let m = OverlayModel()
    m.staticRender = true; m.shown = true; m.style = .notch; m.notchHeight = 32; m.phase = .done(t)
    let probe = NSHostingController(rootView: CardContent(m: m, measuring: true)
        .frame(width: 600 - 2 * Metrics.ear).fixedSize(horizontal: false, vertical: true))
    let notchHeight = 32 + ceil(probe.sizeThatFits(in: CGSize(width: 600, height: 1000)).height)
    save("notch", CGSize(width: 1440, height: 220), ZStack(alignment: .top) {
        Wallpaper()
        VStack(spacing: 0) {
            OverlayView(m: m) {}.frame(width: 600, height: notchHeight).environment(\.colorScheme, .dark)
            Caption(text: "When an app doesn't say where the text is, the translation slides out of the notch")
                .padding(.top, 34)
        }
    })
}

// MARK: - запуск

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
Task { @MainActor in
    let b = Browser()
    await readingScene(b)
    await fieldScene(b)
    await notchScene()
    exit(0)
}
app.run()
