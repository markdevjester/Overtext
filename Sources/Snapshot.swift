import AppKit
import SwiftUI

/// Картинки состояний без показа окон: OVERTEXT_SNAPSHOT=<папка>.
enum Snapshot {
    static let sampleEN = """
    Good tools stay out of your way. Select a paragraph, press a key, and keep reading.

    No windows to manage, no tabs to switch, nothing to copy and paste.
    """
    static let sampleRU = """
    Хорошие инструменты не мешают. Выделите абзац, нажмите клавишу и читайте дальше.

    Никаких окон, переключения вкладок и копирования туда-сюда.
    """

    @MainActor
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        func shot<V: View>(_ name: String, _ size: CGSize, _ view: V) {
            let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("не получилось:", name); return
            }
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            print("готово:", name)
        }

        func model(_ style: OverlayModel.Style, _ phase: OverlayModel.Phase, lines: Int = 4) -> OverlayModel {
            let m = OverlayModel()
            m.staticRender = true
            m.shown = true
            m.style = style
            m.phase = phase
            m.fontSize = 15
            m.lines = lines
            m.notchHeight = 32
            return m
        }

        let page = Color(red: 0.04, green: 0.07, blue: 0.08)
        let original = Text(sampleEN).font(.system(size: 15)).foregroundStyle(.white.opacity(0.9)).lineSpacing(3)

        // как выглядит страница до и после
        let done = model(.inPlace, .done(Translation(text: sampleRU, source: "en", target: "ru")))
        shot("in-place", CGSize(width: 640, height: 260), ZStack(alignment: .topLeading) {
            page
            original.frame(width: 560, alignment: .leading).padding(.leading, 40).padding(.top, 40)
            OverlayView(m: done) {}.frame(width: 578, height: 186).padding(.leading, 31).padding(.top, 34)
        })

        let loading = model(.inPlace, .loading, lines: 4)
        shot("loading", CGSize(width: 640, height: 200), ZStack(alignment: .topLeading) {
            page
            original.frame(width: 560, alignment: .leading).padding(.leading, 40).padding(.top, 40)
            OverlayView(m: loading) {}.frame(width: 578, height: 112).padding(.leading, 31).padding(.top, 34)
        })

        let notch = model(.notch, .done(Translation(text: sampleRU, source: "en", target: "ru")))
        shot("notch", CGSize(width: 700, height: 230), ZStack(alignment: .top) {
            Color(white: 0.85)
            OverlayView(m: notch) {}.frame(width: 560, height: 200)
        })

        let msg = model(.notch, .message("Выделите текст и нажмите ⌘E", "text.cursor"))
        shot("message", CGSize(width: 500, height: 100), ZStack(alignment: .top) {
            Color(white: 0.85)
            OverlayView(m: msg) {}.frame(width: 400, height: 80)
        })
    }

    // MARK: картинки для README

    @MainActor
    static func readme(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot<V: View>(_ name: String, _ size: CGSize, _ view: V) {
            let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
            print("готово:", name)
        }
        func model(_ style: OverlayModel.Style, _ phase: OverlayModel.Phase, fs: CGFloat = 16) -> OverlayModel {
            let m = OverlayModel()
            m.staticRender = true; m.shown = true; m.style = style; m.phase = phase
            m.fontSize = fs; m.lines = 3; m.notchHeight = 32
            return m
        }
        let page = Color(red: 0.05, green: 0.07, blue: 0.09)
        let en = "The best tools are the ones you forget are there. Select any text on any page, press ⌘E, and read it in your own language — right where it was. Click anywhere and it's gone."
        let ru = "Лучшие инструменты — те, о существовании которых забываешь. Выделите любой текст на любой странице, нажмите ⌘E и прочитайте его на своём языке — прямо там, где он был. Щёлкните в любом месте, и он исчезнет."

        func label(_ s: String) -> some View {
            Text(s).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase).tracking(1.2).fixedSize()
        }
        func pageText(_ selected: Bool) -> some View {
            Text(en).font(.system(size: 16)).lineSpacing(3.5).foregroundStyle(.white.opacity(0.88))
                .frame(width: 520, alignment: .leading)
                .padding(.vertical, 2)
                .background(selected ? Color(red: 0.2, green: 0.36, blue: 0.62).opacity(0.75) : .clear)
        }
        let done = model(.inPlace, .done(Translation(text: ru, source: "en", target: "ru")))
        shot("page", CGSize(width: 1280, height: 280), HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 18) {
                label("Select text")
                pageText(true)
            }
            Text("⌘E").font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                .fixedSize().padding(.top, 76)
            VStack(alignment: .leading, spacing: 18) {
                label("…and it's translated in place")
                ZStack(alignment: .topLeading) {
                    pageText(false).opacity(0.0)
                    OverlayView(m: done) {}.frame(width: 538, height: 152).offset(x: -9, y: -6)
                }
            }
        }.padding(.horizontal, 50).padding(.top, 50).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(page))

        // строка ввода: русский → английский прямо в поле
        func field(_ text: String, selected: Bool, caret: Bool) -> some View {
            HStack(spacing: 0) {
                Text(text).font(.system(size: 16)).foregroundStyle(.white.opacity(0.92))
                    .padding(.vertical, 1)
                    .background(selected ? Color(red: 0.2, green: 0.36, blue: 0.62).opacity(0.8) : .clear)
                if caret { Rectangle().fill(Color.white).frame(width: 1.5, height: 20).padding(.leading, 1) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(width: 500, height: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.18)))
        }
        shot("field", CGSize(width: 1280, height: 170), HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 18) {
                label("Write in your language, select")
                field("Привет! Скачал твою утилиту на гитхабе, это огонь", selected: true, caret: false)
            }
            Text("⌘E").font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                .fixedSize().padding(.top, 44)
            VStack(alignment: .leading, spacing: 18) {
                label("…and it's replaced with English")
                field("Hi! I downloaded your utility on GitHub, it's fire", selected: false, caret: true)
            }
        }.padding(.horizontal, 50).padding(.top, 50).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(page))

        let notch = model(.notch, .done(Translation(text: "Лучшие инструменты — те, о существовании которых забываешь.", source: "en", target: "ru")))
        shot("notch", CGSize(width: 1000, height: 140), ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.75), Color(red: 0.32, green: 0.38, blue: 0.52)], startPoint: .top, endPoint: .bottom)
            OverlayView(m: notch) {}.frame(width: 560, height: 98)
        })
    }
}
