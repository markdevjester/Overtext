import AppKit
import SwiftUI

final class OverlayModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case done(Translation)
        case message(String, String) // текст, значок
    }
    enum Style { case inPlace, notch }

    @Published var phase: Phase = .loading
    @Published var style: Style = .inPlace
    @Published var fontSize: CGFloat = 15
    @Published var lines = 2
    @Published var shown = false
    @Published var copied = false
    @Published var scrolls = false
    @Published var notchHeight: CGFloat = 32
    var staticRender = false
}

enum Metrics {
    static let padH: CGFloat = 9
    static let padV: CGFloat = 6
    static let ear: CGFloat = 12
    static let radius: CGFloat = 10
}

/// Окно перевода: держится на экране невидимым, чтобы появляться мгновенно и на текущем рабочем столе.
final class OverlayController {
    let model = OverlayModel()
    let panel: NSPanel
    private var monitors: [Any] = []
    private var shownAt = Date.distantPast
    private var hideWork: DispatchWorkItem?
    private var screen: NSScreen?
    private var minHeight: CGFloat = 0

    var isShown: Bool { model.shown }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: OverlayView(m: model) { [weak self] in self?.tapped() })
        host.sizingOptions = [] // размер окна задаём сами, SwiftUI его не трогает
        panel.contentView = host
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.hide()
            self?.panel.orderFrontRegardless()
        }
    }

    // MARK: показ

    func showLoading(_ sel: Selection) {
        cancelHide()
        model.copied = false
        model.scrolls = false
        model.phase = .loading
        guard let r = sel.rect, let s = NSScreen.screens.first(where: { $0.frame.intersects(r) }) else {
            startNotch()
            fit()
            return
        }
        screen = s
        let vis = s.visibleFrame
        let rr = r.intersection(vis).isNull ? r : r.intersection(vis)
        let fs = min(max(sel.fontSize ?? (rr.height < 40 ? rr.height * 0.72 : 15), 11), 28)
        model.style = .inPlace
        model.fontSize = fs
        model.lines = max(1, min(10, Int((rr.height / (fs * 1.38)).rounded())))
        let w = min(max(rr.width + 2 * Metrics.padH, 220), min(900, vis.width - 24))
        let h = rr.height + 2 * Metrics.padV
        minHeight = h
        let f = NSRect(x: rr.minX - Metrics.padH, y: rr.maxY + Metrics.padV - h, width: w, height: h)
        panel.setFrame(clamp(f, vis), display: true)
        present()
    }

    func showResult(_ t: Translation) {
        withAnimation(.easeOut(duration: 0.22)) { model.phase = .done(t) }
        fit()
    }

    func showMessage(_ text: String, icon: String, hideAfter: Double = 1.8) {
        if !model.shown { startNotch() }
        withAnimation(.easeOut(duration: 0.2)) { model.phase = .message(text, icon) }
        fit()
        scheduleHide(after: hideAfter)
    }

    private func startNotch() {
        guard let s = Self.notchScreen() else { return }
        screen = s
        let n = Self.notchSize(s)
        model.style = .notch
        model.notchHeight = n.height
        model.lines = 2
        minHeight = 0
        panel.setFrame(notchFrame(s, width: n.width + 2 * Metrics.ear, height: n.height), display: true)
        present()
    }

    private func present() {
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        shownAt = Date()
        if !model.shown { DispatchQueue.main.async { self.model.shown = true } }
        installMonitors()
    }

    /// Подгоняет окно под содержимое: верхний край стоит на месте, растёт вниз.
    private func fit() {
        guard let s = screen else { return }
        let notch = model.style == .notch
        let width: CGFloat
        if notch {
            if case .message = model.phase { width = 400 } else { width = min(560, s.frame.width - 40) }
        } else {
            width = panel.frame.width
        }
        let contentW = notch ? width - 2 * Metrics.ear : width
        let measured = measure(width: contentW) + (notch ? model.notchHeight : 0)
        let maxH = s.visibleFrame.height * 0.75
        model.scrolls = measured > maxH
        let h = max(min(measured, maxH), minHeight)
        var f: NSRect
        if notch {
            f = notchFrame(s, width: width, height: h)
        } else {
            f = clamp(NSRect(x: panel.frame.minX, y: panel.frame.maxY - h, width: width, height: h), s.visibleFrame)
        }
        animate(to: f)
    }

    private func measure(width: CGFloat) -> CGFloat {
        let probe = NSHostingController(rootView: CardContent(m: model, measuring: true)
            .frame(width: width).fixedSize(horizontal: false, vertical: true))
        return ceil(probe.sizeThatFits(in: CGSize(width: width, height: 10_000)).height)
    }

    private func animate(to f: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(f, display: true)
        }
    }

    private func clamp(_ f: NSRect, _ vis: NSRect) -> NSRect {
        var r = f
        r.origin.x = min(max(r.minX, vis.minX + 8), vis.maxX - r.width - 8)
        if r.minY < vis.minY + 8 { r.origin.y = vis.minY + 8 }
        if r.maxY > vis.maxY { r.origin.y = vis.maxY - r.height }
        return r
    }

    // MARK: скрытие

    func hide() {
        cancelHide()
        removeMonitors()
        guard model.shown else { return }
        model.shown = false
        panel.ignoresMouseEvents = true
        if model.style == .notch, let s = screen {
            let n = Self.notchSize(s)
            animate(to: notchFrame(s, width: n.width + 2 * Metrics.ear, height: n.height))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, !self.model.shown else { return }
            self.panel.alphaValue = 0
        }
    }

    /// Мгновенно, без анимации — перед подстановкой перевода в строку ввода.
    func hideNow() {
        cancelHide()
        removeMonitors()
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) { model.shown = false }
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
    }

    private func scheduleHide(after: Double) {
        cancelHide()
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
    }

    private func cancelHide() { hideWork?.cancel(); hideWork = nil }

    /// Клик по карточке — скопировать перевод. Клик где угодно ещё, прокрутка или клавиша — скрыть.
    private func tapped() {
        guard case .done(let t) = model.phase else { hide(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(t.text, forType: .string)
        model.copied = true
        scheduleHide(after: 0.55)
    }

    private func installMonitors() {
        removeMonitors()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] e in
            guard let self, Date().timeIntervalSince(self.shownAt) > 0.25 else { return }
            if e.type == .scrollWheel, abs(e.scrollingDeltaY) + abs(e.scrollingDeltaX) < 2 { return }
            self.hide()
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    // MARK: чёлка

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    static func notchSize(_ s: NSScreen) -> CGSize {
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        return CGSize(width: 190, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
    }

    private func notchFrame(_ s: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: s.frame.midX - width / 2, y: s.frame.maxY - height, width: width, height: height)
    }
}

// MARK: - Вид

/// Форма чёлки: «ушки» сверху и скругление снизу.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct OverlayView: View {
    @ObservedObject var m: OverlayModel
    var onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let notch = m.style == .notch
        let shape = notch ? AnyShape(NotchShape(top: Metrics.ear, bottom: 22))
                          : AnyShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        ZStack(alignment: .topLeading) {
            if notch {
                Color.black
            } else if m.staticRender {
                Color(white: scheme == .dark ? 0.14 : 0.985) // картинки для README: как материал окна
            } else {
                VisualEffect()
                Color(nsColor: .textBackgroundColor).opacity(0.6)
            }
            CardContent(m: m)
                .padding(.top, notch ? m.notchHeight : 0)
                .padding(.horizontal, notch ? Metrics.ear : 0)
        }
        .clipShape(shape)
        .overlay {
            if !notch {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            }
        }
        .opacity(m.shown ? 1 : 0)
        .scaleEffect(m.shown ? 1 : (notch ? 0.94 : 0.985), anchor: notch ? .top : .topLeading)
        .blur(radius: m.shown ? 0 : 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: m.shown)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

struct CardContent: View {
    @ObservedObject var m: OverlayModel
    var measuring = false

    private var notch: Bool { m.style == .notch }
    private var fs: CGFloat { notch ? 14 : m.fontSize }
    private var fg: Color { notch ? .white : .primary }

    var body: some View {
        VStack(alignment: .leading, spacing: notch ? 8 : 5) {
            switch m.phase {
            case .loading:
                Skeleton(lines: m.lines, fs: fs, color: fg, animated: !measuring && !m.staticRender)
            case .done(let t):
                if m.scrolls && !measuring {
                    ScrollView { textView(t.text) }
                        .frame(maxHeight: .infinity)
                } else {
                    textView(t.text)
                }
                footer(t)
            case .message(let s, let icon):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                    Text(s).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(fg)
            }
        }
        .padding(.horizontal, notch ? 14 : Metrics.padH)
        .padding(.top, notch ? 4 : Metrics.padV)
        .padding(.bottom, notch ? 12 : Metrics.padV)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textView(_ s: String) -> some View {
        Text(s)
            .font(.system(size: fs))
            .lineSpacing(fs * 0.22)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
    }

    private func footer(_ t: Translation) -> some View {
        HStack(spacing: 5) {
            Text("\(Lang.short(t.source)) → \(Lang.short(t.target))")
            Spacer(minLength: 8)
            Image(systemName: m.copied ? "checkmark" : "doc.on.doc")
            Text(m.copied ? L("Скопировано", "Copied") : L("клик — копировать", "click to copy"))
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(fg.opacity(0.4))
    }
}

/// Мерцающие полоски на месте текста, пока идёт перевод.
struct Skeleton: View {
    let lines: Int
    let fs: CGFloat
    let color: Color
    let animated: Bool
    @State private var on = false

    var body: some View {
        VStack(alignment: .leading, spacing: fs * 0.58) {
            ForEach(0..<lines, id: \.self) { i in
                RoundedRectangle(cornerRadius: fs * 0.3, style: .continuous)
                    .fill(color.opacity(on ? 0.16 : 0.07))
                    .frame(height: fs * 0.8)
                    .scaleEffect(x: i == lines - 1 && lines > 1 ? 0.55 : [1, 0.93, 0.97, 0.9][i % 4], y: 1, anchor: .leading)
                    .animation(animated ? .easeInOut(duration: 0.65).repeatForever().delay(Double(i) * 0.07) : nil, value: on)
            }
        }
        .padding(.vertical, fs * 0.15)
        .onAppear { if animated { on = true } }
    }
}
