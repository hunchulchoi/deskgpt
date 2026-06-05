import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UpdateManagerDelegate {
    var window: NSWindow?
    var viewController: DeskGPTViewController?
    private let updateManager = UpdateManager.shared
    private var preferencesWindowController: PreferencesWindowController?
    private var imageContextMenuMonitor: Any?
    private var refreshAccessoryViewController: NSTitlebarAccessoryViewController?
    private let mainWindowFrameKey = "DeskGPTMainWindowFrame"
    
    var pdfWindow: NSWindow?
    var pdfViewController: DeskGPTPDFViewController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("🚀 AppDelegate: applicationDidFinishLaunching starting...")
        
        viewController = DeskGPTViewController()
        print("🚀 AppDelegate: DeskGPTViewController instantiated...")
        
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let win = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        win.title = "DeskGPT"
        win.contentViewController = viewController
        win.delegate = self
        
        self.window = win
        restoreMainWindowFrameIfAvailable(win)
        
        // Make the window visible and key
        win.makeKeyAndOrderFront(nil)
        
        // Bring the window and application strictly to the foreground
        activateMainWindow()
        print("🚀 AppDelegate: Direct NSWindow created, ordered front, and app activated...")
        installTitlebarRefreshButton(on: win)
        updateManager.delegate = self
        updateManager.start()
        updateManager.checkForUpdatesNow()

        setupMenu()
        print("🚀 AppDelegate: setupMenu finished...")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            activateMainWindow()
        }
        return true
    }
    
    // MARK: - NSWindowDelegate: Hide window instead of destroying to keep session active
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == self.window {
            saveMainWindowFrame(sender)
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        saveMainWindowFrame(window)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == self.window else { return }
        saveMainWindowFrame(window)
    }
    
    @objc func togglePDFHelper() {
        if let pdfWin = pdfWindow {
            if pdfWin.isVisible {
                pdfWin.orderOut(nil)
            } else {
                pdfWin.makeKeyAndOrderFront(nil)
            }
            return
        }
        
        // Lazy-instantiate the floating utility PDF Chunker window
        let win = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 450, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "PDF Chunker & Injector"
        
        pdfViewController = DeskGPTPDFViewController()
        pdfViewController?.mainViewController = viewController
        
        win.contentViewController = pdfViewController
        pdfWindow = win
        
        // Keeps the utility tool floated on top of the chat view
        win.level = .floating
        win.makeKeyAndOrderFront(nil)
    }
    
    private func setupMenu() {
        let mainMenu = NSMenu()
        
        // 1. DeskGPT App Menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DeskGPT", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let preferencesItem = appMenu.addItem(withTitle: "Preferences...", action: #selector(showPreferencesAction), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide DeskGPT", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit DeskGPT", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. File Menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "뒤로 가기 (Go Back)", action: #selector(goBackAction), keyEquivalent: "[")
        fileMenu.addItem(withTitle: "앞으로 가기 (Go Forward)", action: #selector(goForwardAction), keyEquivalent: "]")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "새로고침 (Reload)", action: #selector(reloadAction), keyEquivalent: "r")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "창 닫기 (Close Window)", action: #selector(closeWindowAction), keyEquivalent: "w")
        
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // 3. Edit Menu (Crucial for Cmd+C / Cmd+V / Cmd+A functionality within text fields)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 4. View Menu (Zooming, Always on Top, PDF Chunker toggles)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "확대 (Zoom In)", action: #selector(zoomInAction), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "축소 (Zoom Out)", action: #selector(zoomOutAction), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "화면 배율 기본값 초기화", action: #selector(zoomResetAction), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        
        let topItem = viewMenu.addItem(withTitle: "항상 위에 유지 (Always on Top)", action: #selector(toggleAlwaysOnTopAction), keyEquivalent: "T")
        topItem.keyEquivalentModifierMask = [.command, .shift]
        
        viewMenu.addItem(NSMenuItem.separator())
        let pdfItem = viewMenu.addItem(withTitle: "PDF Chunker & Injector 켜기/끄기", action: #selector(togglePDFHelper), keyEquivalent: "p")
        pdfItem.keyEquivalentModifierMask = [.command, .shift]
        
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // 5. Help / Diagnostic Menu
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "세션 초기화 및 재시작 (Reset Session & Restart)", action: #selector(resetSessionAction), keyEquivalent: "")
        
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    // MARK: - Action Delegates forwarding events to controllers
    @objc func goBackAction() { viewController?.goBack() }
    @objc func goForwardAction() { viewController?.goForward() }
    @objc func reloadAction() { viewController?.reloadPage() }
    @objc func closeWindowAction() { window?.orderOut(nil) }
    @objc func zoomInAction() { viewController?.zoomIn() }
    @objc func zoomOutAction() { viewController?.zoomOut() }
    @objc func zoomResetAction() { viewController?.resetZoom() }
    @objc func showPreferencesAction() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }

        preferencesWindowController?.showWindow(nil)
    }
    
    @objc func toggleAlwaysOnTopAction() {
        guard let win = self.window else { return }
        if win.level == .floating {
            win.level = .normal
            print("🚀 AppDelegate: Always-on-top OFF")
        } else {
            win.level = .floating
            print("🚀 AppDelegate: Always-on-top ON")
        }
    }
    
    @objc func resetSessionAction() { viewController?.resetSession() }

    private func installTitlebarRefreshButton(on window: NSWindow) {
        let button = NSButton(title: "", target: self, action: #selector(reloadAction))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.isTransparent = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "새로고침"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "새로고침")
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 42, height: 30))
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .left
        refreshAccessoryViewController = accessory
        window.addTitlebarAccessoryViewController(accessory)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            viewController?.handleIncomingURL(url)
        }

        activateMainWindow()
        viewController?.activateForExternalPrompt()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let window = window {
            saveMainWindowFrame(window)
        }
        updateManager.stop()
    }

    func updateManager(_ manager: UpdateManager, didPrepareUpdate version: String, downloadURL: URL) {
        viewController?.showUpdateAvailable(version: version, downloadPath: downloadURL)
    }

    private func activateMainWindow() {
        guard let window = window else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKey()
    }

    private func restoreMainWindowFrameIfAvailable(_ window: NSWindow) {
        if let frameString = UserDefaults.standard.string(forKey: mainWindowFrameKey) {
            let frame = NSRectFromString(frameString)
            if frame.width > 0, frame.height > 0 {
                window.setFrame(frame, display: false)
                return
            }
        }

        window.center()
    }

    private func saveMainWindowFrame(_ window: NSWindow) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: mainWindowFrameKey)
    }

    private func installImageContextMenuMonitor() {
        guard imageContextMenuMonitor == nil else { return }

        imageContextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self = self,
                  let viewController = self.viewController,
                  let webView = viewController.webView as? DeskGPTWebView
            else {
                return event
            }

            let isRightClick = event.type == .rightMouseDown
            let isControlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            guard isRightClick || isControlClick else {
                return event
            }

            guard webView.cachedContextMenuImageUrl != nil else {
                return event
            }

            let viewPoint = webView.convert(event.locationInWindow, from: nil)
            guard webView.bounds.contains(viewPoint) else {
                return event
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                guard let refreshedImageUrl = (viewController.webView as? DeskGPTWebView)?.cachedContextMenuImageUrl ?? webView.cachedContextMenuImageUrl else {
                    return
                }
                viewController.presentImageContextMenu(imageUrl: refreshedImageUrl, viewPoint: viewPoint)
            }

            return nil
        }
    }
}
