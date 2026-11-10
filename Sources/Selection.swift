import AppKit
import ApplicationServices

/// Выделенный текст в чужом приложении.
struct Selection {
    var text: String
    var rect: CGRect?          // где он на экране (координаты Cocoa, начало внизу слева)
    var editable: Bool         // это строка ввода — перевод можно подставить вместо текста
    var fontSize: CGFloat?
}

/// Чтение выделения через «Универсальный доступ».
enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func askTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    static func param(_ el: AXUIElement, _ name: String, _ arg: AnyObject) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, arg, &v) == .success ? v : nil
    }

    static func element(_ v: AnyObject?) -> AXUIElement? {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func focused(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        if let f = element(attr(app, kAXFocusedUIElementAttribute)) { return f }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.4)
        return element(attr(sys, kAXFocusedUIElementAttribute))
    }

    static func read(pid: pid_t) -> Selection? {
        let f = focused(pid: pid)
        Log.write("focused=\(f.flatMap { attr($0, kAXRoleAttribute) as? String } ?? "nil")")
        if let el = f, let s = read(element: el) { return s }
        // фокус в адресной строке или его нет — ищем область страницы в активном окне
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let win = element(attr(app, kAXFocusedWindowAttribute)),
              let web = find(role: "AXWebArea", in: win) else { return nil }
        return read(element: web)
    }

    /// Поиск в ширину, с ограничением, чтобы не застрять на огромных страницах.
    static func find(role: String, in root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var seen = 0
        while !queue.isEmpty, seen < 300 {
            let e = queue.removeFirst()
            seen += 1
            if attr(e, kAXRoleAttribute) as? String == role { return e }
            if let kids = attr(e, kAXChildrenAttribute) as? [AnyObject] {
                queue += kids.compactMap(element)
            }
        }
        return nil
    }

    static func read(element el: AXUIElement) -> Selection? {
        AXUIElementSetMessagingTimeout(el, 0.4)
        let role = attr(el, kAXRoleAttribute) as? String ?? ""
        var text = attr(el, kAXSelectedTextAttribute) as? String
        var rect: CGRect?
        var font: CGFloat?

        // обычные поля и текстовые области: диапазон символов
        if let rv = attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(rv) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rv as! AXValue, .cfRange, &range), range.length > 0 {
                if let b = param(el, kAXBoundsForRangeParameterizedAttribute, rv) { rect = cgRect(b) }
                var head = CFRange(location: range.location, length: min(range.length, 200))
                if let hv = AXValueCreate(.cfRange, &head),
                   let a = param(el, kAXAttributedStringForRangeParameterizedAttribute, hv) as? NSAttributedString {
                    font = fontSize(a)
                }
            }
        }
        // страницы в Safari, Chrome и других браузерах: текстовые маркеры
        if rect == nil || (text ?? "").isEmpty, let m = attr(el, "AXSelectedTextMarkerRange") {
            if (text ?? "").isEmpty, let s = param(el, "AXStringForTextMarkerRange", m) as? String { text = s }
            if rect == nil, let b = param(el, "AXBoundsForTextMarkerRange", m) { rect = cgRect(b) }
            if font == nil, let a = param(el, "AXAttributedStringForTextMarkerRange", m) as? NSAttributedString {
                font = fontSize(a)
            }
        }

        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        var editable = editableRoles.contains(role)
            || (role != "AXWebArea" && settable(el, kAXValueAttribute))
            || element(attr(el, "AXEditableAncestor")) != nil
        if !editable, let m = attr(el, "AXSelectedTextMarkerRange") { editable = editableAt(start: m, in: el) }
        // фокус может стоять на любом элементе страницы — поднимаемся до неё и спрашиваем там
        if !editable, let web = ancestor(of: el, role: "AXWebArea"), let m = attr(web, "AXSelectedTextMarkerRange") {
            editable = editableAt(start: m, in: web)
        }
        Log.write("read role=\(role) editable=\(editable) rect=\(rect != nil) font=\(font ?? 0) chars=\(t.count)")
        return Selection(text: t, rect: rect.flatMap(toCocoa), editable: editable, fontSize: font)
    }

    static func ancestor(of el: AXUIElement, role: String) -> AXUIElement? {
        var e: AXUIElement? = el
        for _ in 0..<40 {
            guard let cur = e else { return nil }
            if attr(cur, kAXRoleAttribute) as? String == role { return cur }
            e = element(attr(cur, kAXParentAttribute))
        }
        return nil
    }

    static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Редакторы на страницах (пост Reddit, письмо в Gmail) — это обычный текст внутри
    /// редактируемой области. Смотрим на элемент, где начинается выделение, и его родителей.
    static func editableAt(start m: AnyObject, in el: AXUIElement) -> Bool {
        guard CFGetTypeID(m) == AXTextMarkerRangeGetTypeID() else { return false }
        let start = AXTextMarkerRangeCopyStartMarker(m as! AXTextMarkerRange)
        guard let e = element(param(el, "AXUIElementForTextMarker", start)) else { return false }
        if element(attr(e, "AXEditableAncestor")) != nil { return true }
        return editableRoles.contains(attr(e, kAXRoleAttribute) as? String ?? "")
    }

    static func settable(_ el: AXUIElement, _ name: String) -> Bool {
        var s = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(el, name as CFString, &s) == .success && s.boolValue
    }

    static func cgRect(_ v: AnyObject) -> CGRect? {
        guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        return AXValueGetValue(v as! AXValue, .cgRect, &r) ? r : nil
    }

    /// AX считает от верхнего левого угла главного экрана, Cocoa — от нижнего левого.
    static func toCocoa(_ r: CGRect) -> CGRect? {
        guard r.width > 2, r.height > 2, let main = NSScreen.screens.first else { return nil }
        let c = CGRect(x: r.minX, y: main.frame.height - r.maxY, width: r.width, height: r.height)
        return NSScreen.screens.contains { $0.frame.intersects(c) } ? c : nil
    }

    static func fontSize(_ a: NSAttributedString) -> CGFloat? {
        guard a.length > 0 else { return nil }
        let attrs = a.attributes(at: min(a.length - 1, a.length / 2), effectiveRange: nil)
        guard let f = attrs[NSAttributedString.Key("AXFont")] as? [String: Any],
              let s = f["AXFontSize"] as? NSNumber else { return nil }
        return CGFloat(truncating: s)
    }

    /// Chrome, Arc, Edge, Яндекс и программы на Electron включают доступ к тексту страницы
    /// только по просьбе. Просим один раз на процесс, когда приложение становится активным.
    private static var asked = Set<pid_t>()
    static func wakeWebAccessibility(_ app: NSRunningApplication) {
        guard trusted, app.processIdentifier != getpid(), !asked.contains(app.processIdentifier) else { return }
        asked.insert(app.processIdentifier)
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.3)
        AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}

/// Запасной путь через буфер: ⌘C и ⌘V с возвратом того, что в буфере было.
@MainActor
enum Clip {
    nonisolated static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Просим NotchStash и другие менеджеры буфера markdev не сохранять наши временные копии.
    static func pauseManagers() {
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.markdev.clipboard.pause"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    struct Saved {
        let items: [[NSPasteboard.PasteboardType: Data]]
        init(_ pb: NSPasteboard) {
            items = (pb.pasteboardItems ?? []).map { item in
                var d: [NSPasteboard.PasteboardType: Data] = [:]
                for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
                return d
            }
        }
        func restore(_ pb: NSPasteboard) {
            pb.clearContents()
            let objs = items.map { d -> NSPasteboardItem in
                let i = NSPasteboardItem()
                for (t, v) in d { i.setData(v, forType: t) }
                i.setData(Data(), forType: Clip.transient)
                return i
            }
            if !objs.isEmpty { pb.writeObjects(objs) }
        }
    }

    static func press(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func copySelection() async -> String? {
        let pb = NSPasteboard.general
        pauseManagers()
        let saved = Saved(pb)
        let before = pb.changeCount
        press(8) // C
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before { break }
        }
        guard pb.changeCount != before else { return nil }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let s = pb.string(forType: .string)
        saved.restore(pb)
        return s?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Вставляет текст вместо выделения (⌘V) — так работает отмена ⌘Z в любой программе.
    static func paste(_ text: String) async {
        let pb = NSPasteboard.general
        pauseManagers()
        let saved = Saved(pb)
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transient)
        pb.writeObjects([item])
        press(9) // V
        try? await Task.sleep(nanoseconds: 500_000_000)
        saved.restore(pb)
    }
}

/// Короткий журнал для отладки, без выделенного текста: ~/Library/Logs/Overtext.log
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Overtext.log")
    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
