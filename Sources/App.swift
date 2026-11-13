import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var status: NSStatusItem!
    private var hotKey: HotKey?
    private let overlay = OverlayController()
    private var generation = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Overtext")
        status.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        hotKey = HotKey(id: 1, keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey)) { [weak self] in
            self?.trigger()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                AX.wakeWebAccessibility(app)
            }
            self?.overlay.hide()
        }
        if let front = NSWorkspace.shared.frontmostApplication { AX.wakeWebAccessibility(front) }

        if let bid = ProcessInfo.processInfo.environment["OVERTEXT_AUTOTEST"] { autotest(bid); return }
        if !AX.trusted { AX.askTrust() }
    }

    /// Проверка без нажатий: перевести выделение в указанном приложении, не переключаясь на него.
    private func autotest(_ bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("AUTOTEST нет приложения", bundleID); exit(1)
        }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        run(pid: app.processIdentifier)
        for t in [0.15, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [self] in
                print("AUTOTEST t=\(t) shown=\(overlay.isShown) frame=\(overlay.panel.frame) key=\(overlay.panel.isKeyWindow) phase=\(overlay.model.phase)".prefix(400))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { [self] in
            overlay.hide()
            let after = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
            print("AUTOTEST front before=\(front) after=\(after)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
        }
    }

    // MARK: ⌘E

    private func trigger() {
        if overlay.isShown { overlay.hide(); return }
        guard AX.trusted else {
            AX.askTrust()
            overlay.showMessage(L("Разрешите Overtext в Настройках → Конфиденциальность → Универсальный доступ",
                                  "Allow Overtext in Settings → Privacy & Security → Accessibility"),
                                icon: "lock.shield", hideAfter: 4)
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        AX.wakeWebAccessibility(front)
        run(pid: front.processIdentifier)
    }

    private func run(pid: pid_t) {
        generation += 1
        let gen = generation

        Task { @MainActor in
            var sel = AX.read(pid: pid)
            if sel == nil, let s = await Clip.copySelection(), !s.isEmpty {
                sel = Selection(text: s, rect: nil, editable: false, fontSize: nil)
            }
            guard gen == generation else { return }
            guard let sel else {
                overlay.showMessage(L("Выделите текст и нажмите ⌘E", "Select some text and press ⌘E"),
                                    icon: "text.cursor")
                return
            }

            Log.write("⌘E app=\(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "-") editable=\(sel.editable) rect=\(sel.rect != nil)")
            overlay.showLoading(sel)
            do {
                let t = try await Translator.translate(sel.text)
                guard gen == generation else { return }
                // свой текст в строке ввода — заменить. Язык берём из ответа Google: определитель
                // macOS путается на русском с английскими словами («работает ли API»)
                let replace = sel.editable && Lang.base(t.source) == Lang.base(Lang.native) && t.target == Lang.second
                Log.write("translated \(t.source)→\(t.target) replace=\(replace)")
                if replace {
                    overlay.hideNow()
                    await Clip.paste(t.text)
                } else {
                    overlay.showResult(t)
                }
            } catch {
                guard gen == generation else { return }
                Log.write("translate failed: \(error)")
                switch error as? TranslateError {
                case .offline?:
                    overlay.showMessage(L("Нет связи с Google Translate — проверьте интернет",
                                          "Can't reach Google Translate — check your connection"),
                                        icon: "wifi.exclamationmark", hideAfter: 2.5)
                case .blocked?:
                    overlay.showMessage(L("Google временно ограничил запросы с этой сети — попробуйте через пару минут",
                                          "Google is limiting requests from this network — try again in a few minutes"),
                                        icon: "hourglass", hideAfter: 3.5)
                default:
                    overlay.showMessage(L("Не получилось перевести — попробуйте ещё раз",
                                          "Couldn't translate — please try again"),
                                        icon: "exclamationmark.triangle", hideAfter: 2.5)
                }
            }
        }
    }

    // MARK: меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let head = NSMenuItem(title: L("Выделите текст и нажмите ⌘E", "Select text and press ⌘E"), action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        menu.addItem(languageMenu(title: L("Переводить на", "Translate into"), current: Lang.native, action: #selector(setNative)))
        menu.addItem(languageMenu(title: L("Свой текст — на", "My own text into"), current: Lang.second, action: #selector(setSecond)))
        menu.addItem(item(L("Мой словарь названий…", "My Dictionary…"), #selector(openDictionary)))
        menu.addItem(.separator())

        if !AX.trusted {
            menu.addItem(item(L("Разрешить Универсальный доступ…", "Allow Accessibility…"), #selector(openAccessibility)))
        }
        let login = item(L("Запускать при входе", "Launch at Login"), #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item(L("Выйти", "Quit Overtext"), #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return i
    }

    private func languageMenu(title: String, current: String, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(Lang.name(current))", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (code, name) in Lang.all {
            let i = NSMenuItem(title: name, action: action, keyEquivalent: "")
            i.target = self
            i.representedObject = code
            i.state = code == current ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func setNative(_ s: NSMenuItem) {
        guard let code = s.representedObject as? String else { return }
        if code == Lang.second { Lang.second = Lang.native }
        Lang.native = code
    }

    @objc private func setSecond(_ s: NSMenuItem) {
        guard let code = s.representedObject as? String else { return }
        if code == Lang.native { Lang.native = Lang.second }
        Lang.second = code
    }

    @objc private func openDictionary() {
        let url = Glossary.userFile
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Glossary.userTemplate.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAccessibility() {
        AX.askTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch {
            NSSound.beep()
        }
    }
}
