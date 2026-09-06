import Cocoa
import ServiceManagement
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var isHidden = false
    var previousHidden: Bool? = nil
    var toggleItem: NSMenuItem!
    var undoItem: NSMenuItem!
    var launchAtLoginItem: NSMenuItem!
    var notificationsItem: NSMenuItem!
    var hideWidgetsItem: NSMenuItem!
    var menu: NSMenu!
    var globalHotkeyMonitor: Any?
    var restoreTimer: Timer?
    var pulseTimer: Timer?
    var pulsePhase = false

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }

    var hideWidgetsWithIcons: Bool {
        get { UserDefaults.standard.bool(forKey: "hideWidgetsWithIcons") }
        set { UserDefaults.standard.set(newValue, forKey: "hideWidgetsWithIcons") }
    }

    var widgetHiddenBeforeToggle: Bool? {
        get {
            guard let value = UserDefaults.standard.object(forKey: "widgetHiddenBeforeToggle") else {
                return nil
            }
            return (value as? NSNumber)?.boolValue
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: "widgetHiddenBeforeToggle")
            } else {
                UserDefaults.standard.removeObject(forKey: "widgetHiddenBeforeToggle")
            }
        }
    }

    var desktopWidgetsSupported: Bool {
        if #available(macOS 14.0, *) {
            return true
        }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "hideWidgetsWithIcons": true
        ])

        UNUserNotificationCenter.current().delegate = self

        // Read current Finder state
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.finder", "CreateDesktop"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        isHidden = (output == "0" || output == "false")

        if isHidden && hideWidgetsWithIcons && desktopWidgetsSupported {
            if widgetHiddenBeforeToggle == nil {
                widgetHiddenBeforeToggle = readWindowManagerBoolean("StandardHideWidgets")
            }
            _ = writeWindowManagerBoolean("StandardHideWidgets", value: true)
        }

        // Status item — left click toggles, right click opens menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Build menu
        menu = NSMenu()
        menu.delegate = self

        toggleItem = NSMenuItem(title: "", action: #selector(toggleDesktop), keyEquivalent: "h")
        toggleItem.keyEquivalentModifierMask = [.option, .command]
        toggleItem.target = self
        menu.addItem(toggleItem)

        undoItem = NSMenuItem(title: "Undo", action: #selector(undoToggle), keyEquivalent: "z")
        undoItem.target = self
        undoItem.isEnabled = false
        menu.addItem(undoItem)

        menu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        notificationsItem = NSMenuItem(title: "Notify on Toggle", action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsItem.target = self
        menu.addItem(notificationsItem)

        hideWidgetsItem = NSMenuItem(title: "Hide Widgets with Desktop Icons", action: #selector(toggleHideWidgets), keyEquivalent: "")
        hideWidgetsItem.target = self
        menu.addItem(hideWidgetsItem)

        menu.addItem(NSMenuItem.separator())

        let bugItem = NSMenuItem(title: "Report a Bug", action: #selector(reportBug), keyEquivalent: "")
        bugItem.target = self
        menu.addItem(bugItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        NSApp.setActivationPolicy(.accessory)

        // Global hotkey: ⌥⌘H (keyCode 4 = H)
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.option, .command, .shift, .control])
            guard flags == [.option, .command], event.keyCode == 4 else { return }
            self?.toggleDesktop()
        }

        updateUI()
        refreshNotificationAuthorization()
    }

    // Left click: instant toggle. Right click: menu.
    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            updateLaunchAtLoginItem()   // always fresh on open
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        } else {
            toggleDesktop()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc func toggleDesktop() {
        let newHidden = !isHidden
        guard setDesktopHidden(newHidden, rememberPrevious: true) else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

        if notificationsEnabled {
            sendToggleNotification()
        }

        // Restoring takes longer than hiding — show a pulsing indicator
        if !isHidden {
            showRestoreIndicator()
        } else {
            updateUI()
        }
    }

    @objc func undoToggle() {
        guard let prev = previousHidden else { return }
        guard setDesktopHidden(prev, rememberPrevious: false) else { return }
        previousHidden = nil

        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

        if !isHidden {
            showRestoreIndicator()
        } else {
            updateUI()
        }
    }

    func setDesktopHidden(_ hidden: Bool, rememberPrevious: Bool) -> Bool {
        let value = hidden ? "false" : "true"
        guard runDefaults(arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", value]) else {
            return false
        }

        if rememberPrevious {
            previousHidden = isHidden
        }

        if hideWidgetsWithIcons && desktopWidgetsSupported {
            if hidden {
                if widgetHiddenBeforeToggle == nil {
                    widgetHiddenBeforeToggle = readWindowManagerBoolean("StandardHideWidgets")
                }
                _ = writeWindowManagerBoolean("StandardHideWidgets", value: true)
            } else if let previousWidgetState = widgetHiddenBeforeToggle {
                _ = writeWindowManagerBoolean("StandardHideWidgets", value: previousWidgetState)
                widgetHiddenBeforeToggle = nil
            }
        }

        isHidden = hidden

        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["-HUP", "Finder"]
        try? killTask.run()

        return true
    }

    func readWindowManagerBoolean(_ key: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.WindowManager", key]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return output == "1" || output == "true"
    }

    func writeWindowManagerBoolean(_ key: String, value: Bool) -> Bool {
        return runDefaults(arguments: [
            "write", "com.apple.WindowManager", key, "-bool", value ? "true" : "false"
        ])
    }

    func runDefaults(arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = arguments
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    @objc func toggleHideWidgets() {
        let shouldHide = !hideWidgetsWithIcons
        hideWidgetsWithIcons = shouldHide

        guard desktopWidgetsSupported else {
            updateHideWidgetsItem()
            return
        }

        if isHidden {
            if shouldHide {
                if widgetHiddenBeforeToggle == nil {
                    widgetHiddenBeforeToggle = readWindowManagerBoolean("StandardHideWidgets")
                }
                _ = writeWindowManagerBoolean("StandardHideWidgets", value: true)
            } else if let previousWidgetState = widgetHiddenBeforeToggle {
                _ = writeWindowManagerBoolean("StandardHideWidgets", value: previousWidgetState)
                widgetHiddenBeforeToggle = nil
            }
        }

        updateHideWidgetsItem()
    }

    // Pulses arrow.clockwise ↔ grid for ~2s while Finder reloads the desktop
    func showRestoreIndicator() {
        updateToggleItem()
        updateUndoItem()
        updateLaunchAtLoginItem()
        updateNotificationsItem()
        if let button = statusItem.button {
            button.toolTip = "Desktop icons: restoring…"
        }

        pulseTimer?.invalidate()
        restoreTimer?.invalidate()
        pulsePhase = false

        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulsePhase.toggle()
            let symbol = self.pulsePhase ? "arrow.clockwise" : "square.grid.2x2"
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hidecons") {
                image.isTemplate = true
                self.statusItem.button?.image = image
            }
        }

        restoreTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.pulseTimer?.invalidate()
            self?.updateUI()
        }
    }

    @objc func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            } else {
                try? SMAppService.mainApp.register()
            }
        } else {
            let plistPath = (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/LaunchAgents/com.hidecons.app.plist")
            if FileManager.default.fileExists(atPath: plistPath) {
                try? FileManager.default.removeItem(atPath: plistPath)
            } else {
                let execPath = ProcessInfo.processInfo.arguments[0]
                let plist: [String: Any] = [
                    "Label": "com.hidecons.app",
                    "ProgramArguments": [execPath],
                    "RunAtLoad": true
                ]
                (plist as NSDictionary).write(toFile: plistPath, atomically: true)
            }
        }
        updateLaunchAtLoginItem()
    }

    @objc func toggleNotifications() {
        if notificationsEnabled {
            notificationsEnabled = false
            updateNotificationsItem()
        } else {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                DispatchQueue.main.async {
                    self.notificationsEnabled = granted && error == nil
                    self.updateNotificationsItem()

                    if !self.notificationsEnabled {
                        self.showNotificationPermissionAlert()
                    }
                }
            }
        }
    }

    func refreshNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let canDeliver = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional

            DispatchQueue.main.async {
                if self.notificationsEnabled && !canDeliver {
                    self.notificationsEnabled = false
                    self.updateNotificationsItem()
                }
            }
        }
    }

    func showNotificationPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Hidecons notifications are disabled"
        alert.informativeText = "Enable alerts for Hidecons in System Settings → Notifications, then turn on “Notify on Toggle” again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    @objc func reportBug() {
        NSWorkspace.shared.open(URL(string: "https://github.com/alfaruqstories/hidecons/issues")!)
    }

    @objc func quit() {
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NSApp.terminate(nil)
    }

    func sendToggleNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let canDeliver = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional

            DispatchQueue.main.async {
                guard self.notificationsEnabled else { return }

                guard canDeliver else {
                    self.notificationsEnabled = false
                    self.updateNotificationsItem()
                    self.showNotificationPermissionAlert()
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = "Hidecons"
                content.sound = .default
                content.body = self.isHidden && self.hideWidgetsWithIcons && self.desktopWidgetsSupported
                    ? "Desktop icons and widgets hidden"
                    : self.isHidden ? "Desktop icons hidden" : "Desktop icons visible"

                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(request) { error in
                    guard let error else { return }

                    DispatchQueue.main.async {
                        self.notificationsEnabled = false
                        self.updateNotificationsItem()
                        print("Hidecons notification failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func updateUI() {
        if let button = statusItem.button {
            let symbol = isHidden ? "square.grid.2x2.fill" : "square.grid.2x2"
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hidecons") {
                image.isTemplate = true     // adapts to dark/light menu bar automatically
                button.image = image
            }
            button.toolTip = isHidden ? "Desktop icons: hidden" : "Desktop icons: visible"
        }
        updateToggleItem()
        updateUndoItem()
        updateLaunchAtLoginItem()
        updateNotificationsItem()
        updateHideWidgetsItem()
    }

    func updateToggleItem() {
        toggleItem.title = isHidden ? "Show Desktop Icons" : "Hide Desktop Icons"
    }

    func updateUndoItem() {
        if let prev = previousHidden {
            undoItem.title = prev ? "Undo — Restore Icons" : "Undo — Hide Icons"
            undoItem.isEnabled = true
        } else {
            undoItem.title = "Undo"
            undoItem.isEnabled = false
        }
    }

    func updateLaunchAtLoginItem() {
        if #available(macOS 13.0, *) {
            launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            let plistPath = (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/LaunchAgents/com.hidecons.app.plist")
            launchAtLoginItem.state = FileManager.default.fileExists(atPath: plistPath) ? .on : .off
        }
    }

    func updateNotificationsItem() {
        notificationsItem.state = notificationsEnabled ? .on : .off
    }

    func updateHideWidgetsItem() {
        hideWidgetsItem.state = hideWidgetsWithIcons ? .on : .off
        hideWidgetsItem.isEnabled = desktopWidgetsSupported
        if !desktopWidgetsSupported {
            hideWidgetsItem.title = "Hide Widgets with Desktop Icons (macOS 14+)"
        } else {
            hideWidgetsItem.title = "Hide Widgets with Desktop Icons"
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
