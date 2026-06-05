import Cocoa
import ObjectiveC.runtime
import WebKit

protocol DeskGPTMenuDelegate: AnyObject {
    func webView(_ webView: WKWebView, willOpenMenu menu: NSMenu, with event: NSEvent)
    func webView(_ webView: WKWebView, didRightClickImage imageUrl: URL, with event: NSEvent)
}

class DeskGPTWebView: WKWebView {
    weak var menuDelegate: DeskGPTMenuDelegate?
    var cachedContextMenuImageUrl: URL?
    
    override func menu(for event: NSEvent) -> NSMenu? {
        super.menu(for: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
}

private enum DeskGPTWebKitContextMenuSwizzler {
    static var didInstall = false

    static func install() {
        guard !didInstall else { return }
        didInstall = true

        let targetClassNames = ["WKContentView", "WKApplicationStateTrackingView"]
        for className in targetClassNames {
            guard let targetClass = NSClassFromString(className) else { continue }
            swizzle(targetClass, original: #selector(NSResponder.rightMouseDown(with:)), replacement: #selector(NSView.deskgpt_rightMouseDown(with:)))
            swizzle(targetClass, original: #selector(NSView.menu(for:)), replacement: #selector(NSView.deskgpt_menu(for:)))
        }
    }

    private static func swizzle(_ targetClass: AnyClass, original: Selector, replacement: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(targetClass, original),
            let replacementMethod = class_getInstanceMethod(NSView.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

private extension NSView {
    func deskGPTOwningWebView() -> DeskGPTWebView? {
        var current: NSView? = self
        while let view = current {
            if let webView = view as? DeskGPTWebView {
                return webView
            }
            current = view.superview
        }
        return nil
    }

    func deskGPTViewController() -> DeskGPTViewController? {
        var responder: NSResponder? = self
        while let current = responder {
            if let controller = current as? DeskGPTViewController {
                return controller
            }
            responder = current.nextResponder
        }
        return window?.contentViewController as? DeskGPTViewController
    }

    @objc func deskgpt_menu(for event: NSEvent) -> NSMenu? {
        if let controller = deskGPTViewController(),
           let webView = controller.webView as? DeskGPTWebView,
           let imageUrl = webView.cachedContextMenuImageUrl {
            return controller.makeImageContextMenu(imageUrl: imageUrl)
        }
        return self.deskgpt_menu(for: event)
    }

    @objc func deskgpt_rightMouseDown(with event: NSEvent) {
        if let controller = deskGPTViewController(),
           let webView = controller.webView as? DeskGPTWebView,
           let imageUrl = webView.cachedContextMenuImageUrl {
            let viewPoint = webView.convert(event.locationInWindow, from: nil)
            controller.presentImageContextMenu(imageUrl: imageUrl, viewPoint: viewPoint)
            return
        }
        self.deskgpt_rightMouseDown(with: event)
    }
}

class DeskGPTViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, DeskGPTMenuDelegate, NSMenuDelegate {
    var webView: WKWebView!
    var lastContextMenuImageUrl: URL?
    private let chatGPTHomeURL = URL(string: "https://chatgpt.com")!
    private var loadingOverlayView: NSVisualEffectView?
    private var loadingSpinner: NSProgressIndicator?
    private var loadingLabel: NSTextField?
    private var initialLoadRetryWorkItem: DispatchWorkItem?
    private var initialLoadRetryCount = 0
    private let maximumInitialLoadRetries = 6
    private var updateBannerView: NSVisualEffectView?
    private var updateBannerTitleLabel: NSTextField?
    private var updateBannerDetailLabel: NSTextField?
    private var updateBannerVersion: String?
    private var updateBannerDownloadURL: URL?
    private var pendingExternalPrompt: String?
    private var pendingExternalPromptAttempts: Int = 0
    private var externalPromptRetryTimer: DispatchWorkItem?
    private var composerFocusRetryTimer: DispatchWorkItem?
    private var toastDismissWorkItem: DispatchWorkItem?
    private weak var activeToastView: NSView?
    private var externalPromptPollTimer: DispatchSourceTimer?
    private let raycastInboxURL = URL(fileURLWithPath: "/private/tmp/deskgpt-raycast-inbox.txt")
    
    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        // default persistent datastore preserves cookies, sessions, and local storage across restarts
        webConfiguration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Enable Safari Web Inspector / DevTools for debugging
        webConfiguration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Configure WKUserContentController for JS message posting and script injection
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "directSaveImage")
        userContentController.add(self, name: "saveImageAs")
        userContentController.add(self, name: "copyImage")
        userContentController.add(self, name: "rightClickImageDetected")
        userContentController.add(self, name: "externalPromptStatus")
        
        let jsSource = """
        (function() {
            // 1. Inject styles for the floating download button
            var style = document.createElement('style');
            style.innerHTML = `
                .deskgpt-download-container {
                    position: relative !important;
                }
                .deskgpt-download-btn {
                    position: absolute !important;
                    top: 12px !important;
                    right: 12px !important;
                    z-index: 999999 !important;
                    background: rgba(15, 23, 42, 0.75) !important;
                    backdrop-filter: blur(8px) -webkit-backdrop-filter: blur(8px) !important;
                    border: 1px solid rgba(255, 255, 255, 0.2) !important;
                    border-radius: 6px !important;
                    color: #ffffff !important;
                    padding: 5px 10px !important;
                    font-size: 12px !important;
                    font-weight: 600 !important;
                    cursor: pointer !important;
                    opacity: 0 !important;
                    transition: opacity 0.2s ease-in-out, background 0.15s ease !important;
                    display: flex !important;
                    align-items: center !important;
                    gap: 4px !important;
                    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2) !important;
                }
                .deskgpt-download-btn:hover {
                    background: rgba(15, 23, 42, 0.9) !important;
                    border-color: rgba(255, 255, 255, 0.4) !important;
                }
                /* Reveal button on hover over the container */
                .deskgpt-download-container:hover .deskgpt-download-btn {
                    opacity: 1 !important;
                }
            `;
            document.head.appendChild(style);

            // 2. Attach download buttons only to newly discovered images.
            var processedDownloadImages = new WeakSet();
            var downloadableImageSelector = 'img[src*="oaiusercontent.com"], img[src*="blob:"]';

            function isDownloadableImage(node) {
                return node &&
                    node.tagName === 'IMG' &&
                    node.src &&
                    (node.src.indexOf('oaiusercontent.com') !== -1 || node.src.indexOf('blob:') !== -1);
            }

            function attachDownloadButton(img) {
                if (!isDownloadableImage(img) || processedDownloadImages.has(img)) return;

                var container = img.closest('.relative') || img.parentElement;
                if (!container) return;

                processedDownloadImages.add(img);
                container.classList.add('deskgpt-download-container');

                if (container.querySelector('.deskgpt-download-btn')) return;

                var btn = document.createElement('button');
                btn.className = 'deskgpt-download-btn';
                btn.innerHTML = '⬇️ 저장';
                btn.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();

                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.directSaveImage) {
                        window.webkit.messageHandlers.directSaveImage.postMessage(img.src);
                    } else {
                        alert("Direct save handler is not available. Please restart the app.");
                    }
                });

                container.appendChild(btn);
            }

            function scanAndAttach(root) {
                if (!root || root.nodeType !== Node.ELEMENT_NODE) return;

                if (isDownloadableImage(root)) {
                    attachDownloadButton(root);
                }

                if (!root.querySelectorAll) return;
                root.querySelectorAll(downloadableImageSelector).forEach(attachDownloadButton);
            }

            scanAndAttach(document.body);

            var observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    if (mutation.type === 'attributes') {
                        scanAndAttach(mutation.target);
                        return;
                    }

                    mutation.addedNodes.forEach(scanAndAttach);
                });
            });
            observer.observe(document.body, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['src']
            });

            function resolveImageAtPoint(event) {
                var elements = document.elementsFromPoint(event.clientX, event.clientY);
                var imgSrc = "";

                if (elements && elements.length > 0) {
                    for (var i = 0; i < elements.length; i++) {
                        var el = elements[i];
                        if (!el) continue;

                        if (el.tagName === 'IMG') {
                            imgSrc = el.src || "";
                            break;
                        }
                        if (el.tagName === 'CANVAS') {
                            try {
                                imgSrc = el.toDataURL();
                            } catch (e) {
                                imgSrc = "";
                            }
                            break;
                        }

                        var nestedImg = el.querySelector && el.querySelector('img');
                        if (nestedImg && nestedImg.src) {
                            imgSrc = nestedImg.src;
                            break;
                        }

                        var bg = window.getComputedStyle ? window.getComputedStyle(el).backgroundImage : "";
                        if (bg && bg !== 'none') {
                            var match = bg.match(/url\\(["']?([^"')]+)["']?\\)/);
                            if (match && match[1]) {
                                imgSrc = match[1];
                                break;
                            }
                        }
                    }
                }

                return imgSrc;
            }

            function postRightClickImage(event) {
                if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.rightClickImageDetected) {
                    return false;
                }

                var imgSrc = resolveImageAtPoint(event);
                if (!imgSrc) {
                    return false;
                }

                event.preventDefault();
                event.stopPropagation();
                window.webkit.messageHandlers.rightClickImageDetected.postMessage({
                    url: imgSrc,
                    x: event.clientX,
                    y: event.clientY
                });
                return true;
            }

            window.addEventListener('mousedown', function(event) {
                if (event.button !== 2 && !(event.button === 0 && event.ctrlKey)) {
                    return;
                }
                postRightClickImage(event);
            }, true);

            window.addEventListener('contextmenu', function(event) {
                postRightClickImage(event);
            }, true);

        })();
        """
        let userScript = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(userScript)
        webConfiguration.userContentController = userContentController
        
        let customWebView = DeskGPTWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), configuration: webConfiguration)
        customWebView.menuDelegate = self
        webView = customWebView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        DeskGPTWebKitContextMenuSwizzler.install()
        
        // Set standard macOS Safari User Agent to bypass bot/webview block gates
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        
        self.view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadChatGPTHomePage()
        startRaycastInboxPolling()
    }

    private func loadChatGPTHomePage() {
        initialLoadRetryWorkItem?.cancel()
        let request = URLRequest(url: chatGPTHomeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        showLoadingOverlay(message: "ChatGPT를 불러오는 중...")
        webView.load(request)
    }

    private func scheduleInitialLoadRetry(after delay: TimeInterval) {
        initialLoadRetryWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.loadChatGPTHomePage()
        }

        initialLoadRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func showLoadingOverlay(message: String) {
        DispatchQueue.main.async {
            guard let hostView = self.webView else { return }

            if self.loadingOverlayView == nil {
                let container = NSVisualEffectView()
                container.translatesAutoresizingMaskIntoConstraints = false
                container.wantsLayer = true
                container.material = .hudWindow
                container.blendingMode = .withinWindow
                container.state = .active
                container.layer?.cornerRadius = 18
                container.layer?.masksToBounds = true

                let spinner = NSProgressIndicator()
                spinner.translatesAutoresizingMaskIntoConstraints = false
                spinner.style = .spinning
                spinner.controlSize = .large
                spinner.startAnimation(nil)

                let label = NSTextField(labelWithString: message)
                label.translatesAutoresizingMaskIntoConstraints = false
                label.alignment = .center
                label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
                label.textColor = .white
                label.maximumNumberOfLines = 2
                label.lineBreakMode = .byWordWrapping

                let stack = NSStackView(views: [spinner, label])
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.orientation = .vertical
                stack.alignment = .centerX
                stack.spacing = 12

                container.addSubview(stack)
                hostView.addSubview(container, positioned: .above, relativeTo: nil)

                NSLayoutConstraint.activate([
                    container.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
                    container.centerYAnchor.constraint(equalTo: hostView.centerYAnchor),
                    container.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
                    container.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
                    stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
                    stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),
                    stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
                    stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
                ])

                self.loadingOverlayView = container
                self.loadingSpinner = spinner
                self.loadingLabel = label
            }

            self.loadingLabel?.stringValue = message
            self.loadingSpinner?.startAnimation(nil)
            self.loadingOverlayView?.isHidden = false
            self.loadingOverlayView?.alphaValue = 1.0
        }
    }

    private func hideLoadingOverlay() {
        DispatchQueue.main.async {
            self.loadingOverlayView?.isHidden = true
            self.loadingOverlayView?.alphaValue = 0.0
            self.loadingSpinner?.stopAnimation(nil)
        }
    }

    private func isRecoverableStartupError(_ error: Error?) -> Bool {
        guard let nsError = error as NSError? else { return true }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed:
                return true
            default:
                return false
            }
        }

        if nsError.domain == WKError.errorDomain, nsError.code == WKError.webContentProcessTerminated.rawValue {
            return true
        }

        return false
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "deskgpt" else { return }
        guard url.host?.lowercased() == "ask" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let prompt = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        handleIncomingPrompt(trimmedPrompt)
    }

    func handleIncomingPrompt(_ prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        pendingExternalPrompt = trimmedPrompt
        pendingExternalPromptAttempts = 0
        activateForExternalPrompt()
        attemptToSendPendingExternalPrompt()
    }

    private func currentMouseLocationInWebView() -> CGPoint {
        guard let window = self.webView.window else {
            return CGPoint(x: self.webView.bounds.midX, y: self.webView.bounds.midY)
        }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        return self.webView.convert(windowPoint, from: nil)
    }

    func activateForExternalPrompt() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let window = self.webView.window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }

            self.scheduleComposerFocusRecovery(after: 0.15)
        }
    }
    
    // MARK: - WKUIDelegate: File Upload and New Window Handling
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK {
                completionHandler(openPanel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    // Handle target="_blank" links (essential for image downloads and external links)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                // Open internal and OpenAI hosting CDN links inside the app, and external links in the default browser
                if host.contains("chatgpt.com") || host.contains("openai.com") || host.contains("oaiusercontent.com") {
                    webView.load(navigationAction.request)
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        return nil
    }
    
    // MARK: - WKNavigationDelegate: Intercept Downloads and Outbound Web Routing (macOS 11.3+)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationAction.shouldPerformDownload {
                // Hijack WebKit's default context menu download action ("이미지 다운로드")
                if let url = navigationAction.request.url {
                    let filename = self.getSafeFilename(for: url)
                    let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
                    print("🚀 Intercepted native download request for: \(url.absoluteString)")
                    
                    // Route securely to our custom downloader to sync cookies
                    self.processImageDownload(from: url, to: destinationUrl)
                }
                
                // Cancel the native buggy thread to prevent double downloads and 403 errors
                decisionHandler(.cancel)
                return
            }
        }
        
        // Intercept and route outbound external links safely to default macOS Safari
        if let url = navigationAction.request.url {
            let host = url.host?.lowercased() ?? ""
            
            // Whitelist of domains allowed to remain inside DeskGPT
            let allowedHosts = [
                "chatgpt.com", 
                "openai.com", 
                "oaiusercontent.com", 
                "auth0.com", 
                "appleid.apple.com", 
                "accounts.google.com", 
                "sentry.io"
            ]
            
            // Allow hosts that match exactly or are subdomains of whitelisted domains
            let isAllowed = host.isEmpty || allowedHosts.contains { allowed in
                host == allowed || host.hasSuffix("." + allowed)
            }
            
            if !isAllowed {
                print("🌐 Outbound link routed to Safari: \(url.absoluteString)")
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if #available(macOS 11.3, *) {
            if navigationResponse.canShowMIMEType == false {
                // If it is a download attachment, hijack it cleanly
                if let url = navigationResponse.response.url {
                    let filename = navigationResponse.response.suggestedFilename ?? "file.dat"
                    let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
                    self.processImageDownload(from: url, to: destinationUrl)
                }
                decisionHandler(.cancel)
                return
            }
        }
        
        // Inspect HTTP headers for "Content-Disposition: attachment" (Crucial for ChatGPT image downloads)
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let headers = httpResponse.allHeaderFields as? [String: String],
           let url = navigationResponse.response.url {
            for (key, value) in headers {
                if key.lowercased() == "content-disposition" && value.lowercased().contains("attachment") {
                    let filename = navigationResponse.response.suggestedFilename ?? "file.dat"
                    let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
                    self.processImageDownload(from: url, to: destinationUrl)
                    
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    // MARK: - WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Hijack the WKDownload lifecycle to bypass system NSSavePanel dialogs and cookies issues!
        if let url = response.url {
            let filename = suggestedFilename.isEmpty ? "image.png" : suggestedFilename
            let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
            
            print("🚀 WKDownload Interceptor: Routing native download safely for \(url.absoluteString)")
            
            // Route to our secure cookie-synced Swift URLSession downloader
            self.processImageDownload(from: url, to: destinationUrl)
        }
        
        // Pass nil to the completionHandler to instantly cancel the system Save Panel / native thread
        completionHandler(nil)
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        // No-op here since our custom URLSession downloader handles sounds and completion popups
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        // Log error safely but bypass generic UI alert to avoid interrupting custom downloads
        print("ℹ️ WKDownload thread naturally terminated or bypassed: \(error.localizedDescription)")
    }
    
    // MARK: - Navigation, Zoom, and Utility Controls
    func zoomIn() {
        webView.pageZoom += 0.1
    }
    
    func zoomOut() {
        if webView.pageZoom > 0.5 {
            webView.pageZoom -= 0.1
        }
    }
    
    func resetZoom() {
        webView.pageZoom = 1.0
    }
    
    func reloadPage() {
        initialLoadRetryWorkItem?.cancel()
        initialLoadRetryCount = 0
        webView.reload()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        initialLoadRetryWorkItem?.cancel()
        initialLoadRetryWorkItem = nil
        initialLoadRetryCount = 0
        hideLoadingOverlay()
        attemptToSendPendingExternalPrompt()
        scheduleComposerFocusRecovery(after: 0.25)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        showLoadingOverlay(message: "ChatGPT를 불러오는 중...")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleInitialLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleInitialLoadFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showLoadingOverlay(message: "세션을 복구하는 중...")
        webView.reload()
    }
    
    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    // MARK: - Smart Prompt Injection (Inject text into ChatGPT Input)
    func injectTextIntoChat(_ text: String) {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        let jsScript = """
        (function() {
            var textarea = document.querySelector('#prompt-textarea') || document.querySelector('textarea');
            if (textarea) {
                textarea.focus();
                textarea.value = "\(escapedText)";
                textarea.dispatchEvent(new Event('input', { bubbles: true }));
                return true;
            }
            return false;
        })();
        """
        
        webView.evaluateJavaScript(jsScript) { result, error in
            if let error = error {
                print("Text injection failed: \(error.localizedDescription)")
            } else if let success = result as? Bool, !success {
                // Safe Fallback: Copy to clipboard if textarea not found
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "클립보드 복사 완료"
                    alert.informativeText = "ChatGPT의 입력칸을 자동으로 찾지 못했습니다. 텍스트가 클립보드에 안전하게 복사되었으니 원하시는 곳에 붙여넣기(Cmd+V) 해주세요."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "확인")
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Cache & Session Cleaning
    func resetSession() {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: dateFrom) {
            DispatchQueue.main.async {
                self.reloadPage()
                let alert = NSAlert()
                alert.messageText = "세션 초기화 완료"
                alert.informativeText = "쿠키 및 로컬 캐시가 완전히 삭제되었으며, 앱을 새로고침합니다."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "확인")
                alert.runModal()
            }
        }
    }
    
    // MARK: - DeskGPTMenuDelegate
    func webView(_ webView: WKWebView, willOpenMenu menu: NSMenu, with event: NSEvent) {
        configureImageContextMenu(menu)
    }

    func webView(_ webView: WKWebView, didRightClickImage imageUrl: URL, with event: NSEvent) {
        self.lastContextMenuImageUrl = imageUrl
        (self.webView as? DeskGPTWebView)?.cachedContextMenuImageUrl = imageUrl
        let location = self.webView.convert(event.locationInWindow, from: nil)
        self.presentImageContextMenu(imageUrl: imageUrl, viewPoint: location)
    }

    func menuWillOpen(_ menu: NSMenu) {
        configureImageContextMenu(menu)
    }

    private func configureImageContextMenu(_ menu: NSMenu) {
        // Find if this menu is for an image (has standard image menu items)
        let isImage = menu.items.contains { item in
            let title = item.title.lowercased()
            return title.contains("image") || title.contains("이미지")
        }
        
        if isImage {
            // Remove buggy WebKit save items
            let titlesToRemove = ["save image to downloads", "save image as", "download image", "이미지 저장", "다운로드", "다운로드 폴더에 이미지 저장"]
            menu.items.removeAll { item in
                let title = item.title.lowercased()
                return titlesToRemove.contains { title.contains($0) }
            }
            
            // Determine system preferred language to display native-like Korean/English
            let isKorean = NSLocale.preferredLanguages.first?.hasPrefix("ko") ?? false
            let directTitle = isKorean ? "다운로드 폴더에 이미지 저장" : "Save Image to Downloads"
            let saveAsTitle = isKorean ? "이미지를 다른 이름으로 저장..." : "Save Image As..."
            
            // Find insertion point
            var insertIndex = 0
            for (index, item) in menu.items.enumerated() {
                let title = item.title.lowercased()
                if title.contains("open image in new window") || title.contains("새 창에서 이미지 열기") {
                    insertIndex = max(insertIndex, index + 1)
                } else if title.contains("open image") || title.contains("이미지 열기") {
                    insertIndex = max(insertIndex, index + 1)
                }
            }
            
            // Add custom save-as item
            let saveAsItem = NSMenuItem(title: saveAsTitle, action: #selector(self.customSaveImageAction(_:)), keyEquivalent: "")
            saveAsItem.target = self
            saveAsItem.representedObject = self.lastContextMenuImageUrl
            menu.insertItem(saveAsItem, at: insertIndex)
            
            // Add direct download menu item
            let directItem = NSMenuItem(title: directTitle, action: #selector(self.customSaveImageDirectAction(_:)), keyEquivalent: "")
            directItem.target = self
            directItem.representedObject = self.lastContextMenuImageUrl
            menu.insertItem(directItem, at: insertIndex)
        }
    }
    
    @objc func customSaveImageDirectAction(_ sender: NSMenuItem) {
        guard let imageUrl = self.imageURL(for: sender) else { return }
        let filename = self.getSafeFilename(for: imageUrl)
        let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
        print("🚀 Save Direct: Saving straight to \\(destinationUrl.path)")
        self.processImageDownload(from: imageUrl, to: destinationUrl)
    }
    
    @objc func customSaveImageAction(_ sender: NSMenuItem) {
        guard let imageUrl = self.imageURL(for: sender) else { return }
        self.handleSaveImageAs(url: imageUrl)
    }
    
    // Resolves duplicate filenames inside ~/Downloads by appending a standard counter e.g., image (1).png
    private func getUniqueDownloadsURL(suggestedName: String) -> URL {
        let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let name = suggestedName.isEmpty ? "image.png" : suggestedName
        
        let fileManager = FileManager.default
        var destinationUrl = downloadsUrl.appendingPathComponent(name)
        
        if fileManager.fileExists(atPath: destinationUrl.path) {
            let fileExtension = destinationUrl.pathExtension
            let baseName = destinationUrl.deletingPathExtension().lastPathComponent
            var counter = 1
            while true {
                let newName = "\(baseName) (\(counter)).\(fileExtension)"
                let newUrl = downloadsUrl.appendingPathComponent(newName)
                if !fileManager.fileExists(atPath: newUrl.path) {
                    destinationUrl = newUrl
                    break
                }
                counter += 1
            }
        }
        return destinationUrl
    }
    
    private func getSafeFilename(for url: URL) -> String {
        if url.scheme == "data" {
            return "image.png"
        } else if url.scheme == "blob" {
            return "\(url.lastPathComponent).png"
        } else {
            var filename = url.lastPathComponent
            if filename.isEmpty || filename.count > 100 { return "image.png" }
            if !filename.contains(".") { filename += ".png" }
            return filename
        }
    }
    
    private func processImageDownload(from url: URL, to destination: URL) {
        if url.scheme == "data" {
            self.saveDataURL(url, to: destination)
        } else if url.scheme == "blob" {
            self.downloadBlobURL(url, to: destination)
        } else {
            self.downloadImage(from: url, to: destination)
        }
    }
    
    private func downloadBlobURL(_ url: URL, to destination: URL) {
        let js = """
        (function() {
            return new Promise((resolve, reject) => {
                var xhr = new XMLHttpRequest();
                xhr.open('GET', '\(url.absoluteString)', true);
                xhr.responseType = 'blob';
                xhr.onload = function(e) {
                    if (this.status == 200) {
                        var blob = this.response;
                        var reader = new FileReader();
                        reader.readAsDataURL(blob);
                        reader.onloadend = function() {
                            resolve(reader.result);
                        }
                    } else {
                        reject("Status: " + this.status);
                    }
                };
                xhr.onerror = function() { reject("XHR Error"); };
                xhr.send();
            });
        })();
        """
        
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                self.showErrorAlert(message: "Blob 이미지 추출 실패", info: error.localizedDescription)
                return
            }
            if let dataUrl = result as? String, let dataUrlURL = URL(string: dataUrl) {
                self.saveDataURL(dataUrlURL, to: destination)
            } else {
                self.showErrorAlert(message: "Blob 이미지 추출 실패", info: "알 수 없는 에러가 발생했습니다.")
            }
        }
    }
    
    private func downloadImage(from url: URL, to destination: URL) {
        // Fetch webview cookies to prevent 403 Forbidden errors when downloading protected CDN assets
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            // Map Swift cookies to the request HTTP headers manually
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                if let error = error {
                    self.showErrorAlert(message: "이미지 다운로드 실패", info: error.localizedDescription)
                    return
                }
                
                // Handle HTTP response errors (e.g., 403, 404)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    self.showErrorAlert(message: "이미지 다운로드 실패", info: "서버가 \(httpResponse.statusCode) 에러를 반환했습니다. 세션 만료 혹은 보안 차단일 수 있습니다.")
                    return
                }
                
                guard let data = data else {
                    self.showErrorAlert(message: "이미지 다운로드 실패", info: "데이터가 비어 있습니다.")
                    return
                }
                do {
                    try data.write(to: destination)
                    DispatchQueue.main.async {
                        NSSound.beep()
                        self.showToast(message: "이미지를 저장하였습니다")
                    }
                } catch {
                    self.showErrorAlert(message: "이미지 저장 실패", info: error.localizedDescription)
                }
            }
            task.resume()
        }
    }
    
    private func saveDataURL(_ url: URL, to destination: URL) {
        let urlString = url.absoluteString
        guard let commaIndex = urlString.firstIndex(of: ",") else {
            self.showErrorAlert(message: "이미지 저장 실패", info: "잘못된 Data URL 형식입니다.")
            return
        }
        let base64String = String(urlString[urlString.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            self.showErrorAlert(message: "이미지 저장 실패", info: "Base64 디코딩에 실패했습니다.")
            return
        }
        do {
            try data.write(to: destination)
            DispatchQueue.main.async {
                NSSound.beep()
                self.showToast(message: "이미지를 저장하였습니다")
            }
        } catch {
            self.showErrorAlert(message: "이미지 저장 실패", info: error.localizedDescription)
        }
    }

    private func showToast(message: String) {
        DispatchQueue.main.async {
            guard let hostView = self.webView else { return }

            self.toastDismissWorkItem?.cancel()
            self.activeToastView?.removeFromSuperview()

            let container = NSVisualEffectView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.wantsLayer = true
            container.material = .hudWindow
            container.blendingMode = .withinWindow
            container.state = .active
            container.layer?.cornerRadius = 12
            container.layer?.masksToBounds = true
            container.alphaValue = 0.0

            let label = NSTextField(labelWithString: message)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alignment = .center
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white

            container.addSubview(label)
            hostView.addSubview(container, positioned: .above, relativeTo: nil)

            NSLayoutConstraint.activate([
                container.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
                container.bottomAnchor.constraint(equalTo: hostView.bottomAnchor, constant: -28),
                container.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
                container.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18)
            ])

            hostView.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                container.animator().alphaValue = 1.0
            }

            let dismiss = DispatchWorkItem { [weak container] in
                guard let container = container else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    container.animator().alphaValue = 0.0
                }, completionHandler: {
                    container.removeFromSuperview()
                })
            }
            self.toastDismissWorkItem = dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: dismiss)
            self.activeToastView = container
        }
    }

    func showUpdateAvailable(version: String, downloadPath: URL) {
        DispatchQueue.main.async {
            guard let hostView = self.webView else { return }

            if self.updateBannerVersion == version, self.updateBannerDownloadURL == downloadPath, self.updateBannerView != nil {
                self.updateBannerView?.isHidden = false
                self.updateBannerView?.alphaValue = 1.0
                return
            }

            self.dismissUpdateBanner()

            let container = NSVisualEffectView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.wantsLayer = true
            container.material = .hudWindow
            container.blendingMode = .withinWindow
            container.state = .active
            container.layer?.cornerRadius = 16
            container.layer?.masksToBounds = true
            container.alphaValue = 0.0

            let titleLabel = NSTextField(labelWithString: "새 버전 \(version)을 다운로드했습니다.")
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.maximumNumberOfLines = 2
            titleLabel.lineBreakMode = .byWordWrapping

            let detailLabel = NSTextField(labelWithString: "Restart to Update를 누르면 바로 새 버전으로 재시작됩니다.")
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.maximumNumberOfLines = 2
            detailLabel.lineBreakMode = .byWordWrapping

            let textStack = NSStackView(views: [titleLabel, detailLabel])
            textStack.translatesAutoresizingMaskIntoConstraints = false
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 4

            let restartButton = NSButton(title: "Restart to Update", target: self, action: #selector(self.restartToUpdateAction(_:)))
            restartButton.bezelStyle = .rounded
            restartButton.controlSize = .regular
            restartButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            restartButton.contentTintColor = .white
            restartButton.isBordered = true
            restartButton.translatesAutoresizingMaskIntoConstraints = false

            let laterButton = NSButton(title: "다음 실행에 적용", target: self, action: #selector(self.deferUpdateAction(_:)))
            laterButton.bezelStyle = .texturedRounded
            laterButton.controlSize = .regular
            laterButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            laterButton.translatesAutoresizingMaskIntoConstraints = false

            let actionStack = NSStackView(views: [restartButton, laterButton])
            actionStack.translatesAutoresizingMaskIntoConstraints = false
            actionStack.orientation = .horizontal
            actionStack.alignment = .centerY
            actionStack.spacing = 8

            let contentStack = NSStackView(views: [textStack, actionStack])
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentStack.orientation = .horizontal
            contentStack.alignment = .centerY
            contentStack.spacing = 18

            container.addSubview(contentStack)
            hostView.addSubview(container, positioned: .above, relativeTo: nil)

            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: hostView.topAnchor, constant: 18),
                container.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
                container.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
                contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
                contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
                contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
                contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
                restartButton.heightAnchor.constraint(equalToConstant: 30)
            ])

            container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.78).cgColor

            self.updateBannerView = container
            self.updateBannerTitleLabel = titleLabel
            self.updateBannerDetailLabel = detailLabel
            self.updateBannerVersion = version
            self.updateBannerDownloadURL = downloadPath

            hostView.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                container.animator().alphaValue = 1.0
            }
        }
    }

    func dismissUpdateBanner() {
        DispatchQueue.main.async {
            self.updateBannerView?.removeFromSuperview()
            self.updateBannerView = nil
            self.updateBannerTitleLabel = nil
            self.updateBannerDetailLabel = nil
            self.updateBannerVersion = nil
            self.updateBannerDownloadURL = nil
        }
    }

    @objc private func restartToUpdateAction(_ sender: Any?) {
        guard let downloadURL = updateBannerDownloadURL else { return }
        UpdateInstaller.installAndRelaunch(from: downloadURL)
        NSApp.terminate(nil)
    }

    @objc private func deferUpdateAction(_ sender: Any?) {
        dismissUpdateBanner()
    }
    
    private func showErrorAlert(message: String, info: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = info
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }
}

extension DeskGPTViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "directSaveImage" {
            guard let imageUrlString = message.body as? String, let url = URL(string: imageUrlString) else { return }
            let filename = self.getSafeFilename(for: url)
            let destinationUrl = self.getUniqueDownloadsURL(suggestedName: filename)
            self.processImageDownload(from: url, to: destinationUrl)
        } else if message.name == "saveImageAs" {
            guard let imageUrlString = message.body as? String, let url = URL(string: imageUrlString) else { return }
            self.handleSaveImageAs(url: url)
        } else if message.name == "copyImage" {
            guard let imageUrlString = message.body as? String, let url = URL(string: imageUrlString) else { return }
            self.handleCopyImage(url: url)
        } else if message.name == "rightClickImageDetected" {
            let payload: [String: Any]?
            if let dict = message.body as? [String: Any] {
                payload = dict
            } else if let imageUrlString = message.body as? String, !imageUrlString.isEmpty {
                payload = ["url": imageUrlString]
            } else {
                payload = nil
            }

            guard let payload,
                  let imageUrlString = payload["url"] as? String,
                  let url = URL(string: imageUrlString)
            else {
                self.lastContextMenuImageUrl = nil
                (self.webView as? DeskGPTWebView)?.cachedContextMenuImageUrl = nil
                return
            }

            self.lastContextMenuImageUrl = url
            (self.webView as? DeskGPTWebView)?.cachedContextMenuImageUrl = url
            print("🎯 Cached image URL under cursor: \(url.absoluteString)")
            self.presentImageContextMenu(imageUrl: url, viewPoint: self.currentMouseLocationInWebView())
        } else if message.name == "externalPromptStatus" {
            guard let status = message.body as? String else { return }
            switch status {
            case "sent":
                pendingExternalPrompt = nil
                pendingExternalPromptAttempts = 0
                externalPromptRetryTimer?.cancel()
                externalPromptRetryTimer = nil
                scheduleComposerFocusRecovery(after: 0.35)
            default:
                break
            }
        }
    }
    
    // MARK: - Handlers for Custom HTML Context Menu
    private func handleSaveImageAs(url: URL) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Image"
        savePanel.nameFieldStringValue = self.getSafeFilename(for: url)
        
        savePanel.begin { [weak self] response in
            guard let self = self, response == .OK, let destinationUrl = savePanel.url else { return }
            self.processImageDownload(from: url, to: destinationUrl)
        }
    }
    
    private func handleCopyImage(url: URL) {
        if url.scheme == "data" {
            let urlString = url.absoluteString
            guard let commaIndex = urlString.firstIndex(of: ",") else { return }
            let base64String = String(urlString[urlString.index(after: commaIndex)...])
            guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters),
                  let image = NSImage(data: data) else { return }
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            print("📋 Copied Data URL image to clipboard")
        } else {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                let headers = HTTPCookie.requestHeaderFields(with: cookies)
                for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    guard let data = data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([image])
                        print("📋 Copied image to clipboard")
                    }
                }.resume()
            }
        }
    }

    func presentImageContextMenu(imageUrl: URL, viewPoint: CGPoint) {
        let menu = makeImageContextMenu(imageUrl: imageUrl)
        menu.popUp(positioning: nil, at: viewPoint, in: self.webView)
    }

    private func attemptToSendPendingExternalPrompt() {
        guard let prompt = pendingExternalPrompt else { return }
        guard pendingExternalPromptAttempts < 30 else {
            pendingExternalPrompt = nil
            return
        }

        pendingExternalPromptAttempts += 1
        sendPromptToChatGPT(prompt)

        externalPromptRetryTimer?.cancel()
        let retry = DispatchWorkItem { [weak self] in
            self?.attemptToSendPendingExternalPrompt()
        }
        externalPromptRetryTimer = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: retry)
    }

    private func sendPromptToChatGPT(_ prompt: String) {
        let escapedPrompt = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let js = """
        (function() {
            const prompt = '\(escapedPrompt)';
            const postStatus = (status) => {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.externalPromptStatus) {
                    window.webkit.messageHandlers.externalPromptStatus.postMessage(status);
                }
            };

            const selectors = [
                'textarea[placeholder*="Ask anything"]',
                'textarea[aria-label*="Ask anything"]',
                'textarea',
                '[contenteditable="true"]'
            ];

            let input = null;
            for (const selector of selectors) {
                input = document.querySelector(selector);
                if (input) break;
            }

            if (!input) {
                postStatus('no-input');
                return;
            }

            const dispatchInputEvent = () => {
                input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
            };

            const focusComposer = () => {
                try {
                    if (input.focus) {
                        input.focus({ preventScroll: true });
                    } else {
                        input.focus();
                    }
                } catch (e) {
                    if (input.focus) {
                        input.focus();
                    }
                }

                if (input.scrollIntoView) {
                    input.scrollIntoView({ block: 'center', inline: 'nearest' });
                }
            };

            if (input.tagName === 'TEXTAREA') {
                const descriptor = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
                if (descriptor && descriptor.set) {
                    descriptor.set.call(input, prompt);
                } else {
                    input.value = prompt;
                }
                dispatchInputEvent();
                focusComposer();
            } else {
                focusComposer();
                input.textContent = prompt;
                dispatchInputEvent();
            }

            const trySend = () => {
                const buttons = Array.from(document.querySelectorAll('button'));
                const sendButton = buttons.find((button) => {
                    const label = [
                        button.getAttribute('aria-label') || '',
                        button.getAttribute('title') || '',
                        button.innerText || '',
                        button.textContent || ''
                    ].join(' ').toLowerCase();
                    return /send|전송|보내기|prompt/.test(label) && !button.disabled;
                });

                if (sendButton) {
                    sendButton.click();
                    postStatus('sent');
                    return true;
                }

                if (input && input.dispatchEvent) {
                    focusComposer();
                    input.dispatchEvent(new KeyboardEvent('keydown', {
                        key: 'Enter',
                        code: 'Enter',
                        bubbles: true,
                        cancelable: true
                    }));
                    input.dispatchEvent(new KeyboardEvent('keyup', {
                        key: 'Enter',
                        code: 'Enter',
                        bubbles: true,
                        cancelable: true
                    }));
                    postStatus('sent');
                    return true;
                }

                postStatus('not-ready');
                return false;
            };

            setTimeout(trySend, 250);
        })();
        """

        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("⚠️ Raycast prompt injection failed: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleComposerFocusRecovery(after delay: TimeInterval) {
        composerFocusRetryTimer?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.focusChatComposer()
        }

        composerFocusRetryTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func focusChatComposer() {
        let js = """
        (function() {
            const selectors = [
                '#prompt-textarea',
                'textarea[placeholder*="Ask anything"]',
                'textarea[aria-label*="Ask anything"]',
                'textarea',
                '[contenteditable="true"]'
            ];

            let input = null;
            for (const selector of selectors) {
                input = document.querySelector(selector);
                if (input) break;
            }

            if (!input) {
                return false;
            }

            try {
                if (input.focus) {
                    input.focus({ preventScroll: true });
                } else {
                    input.focus();
                }
            } catch (e) {
                input.focus();
            }

            if (input.scrollIntoView) {
                input.scrollIntoView({ block: 'center', inline: 'nearest' });
            }

            return true;
        })();
        """

        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("⚠️ Composer focus recovery failed: \(error.localizedDescription)")
            }
        }
    }

    private func startRaycastInboxPolling() {
        guard externalPromptPollTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.25, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.pendingExternalPrompt == nil else { return }
            guard FileManager.default.fileExists(atPath: self.raycastInboxURL.path) else { return }

            do {
                let prompt = try String(contentsOf: self.raycastInboxURL, encoding: .utf8)
                try FileManager.default.removeItem(at: self.raycastInboxURL)
                let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPrompt.isEmpty else { return }

                DispatchQueue.main.async {
                    self.handleIncomingPrompt(trimmedPrompt)
                }
            } catch {
                print("⚠️ Failed to read Raycast inbox: \(error.localizedDescription)")
            }
        }
        timer.resume()
        externalPromptPollTimer = timer
    }

    private func handleInitialLoadFailure(_ error: Error) {
        guard isRecoverableStartupError(error) else {
            hideLoadingOverlay()
            showErrorAlert(message: "초기 화면을 불러오지 못했습니다", info: error.localizedDescription)
            return
        }

        guard initialLoadRetryCount < maximumInitialLoadRetries else {
            showLoadingOverlay(message: "네트워크가 준비되면 자동으로 다시 시도합니다.\n필요하면 Cmd+R로 새로고침해 주세요.")
            return
        }

        initialLoadRetryCount += 1
        let delay = min(10.0, pow(1.6, Double(initialLoadRetryCount)))
        showLoadingOverlay(message: "연결을 다시 시도하는 중... (\(initialLoadRetryCount)/\(maximumInitialLoadRetries))")
        scheduleInitialLoadRetry(after: delay)
    }

    func makeImageContextMenu(imageUrl: URL) -> NSMenu {
        let isKorean = NSLocale.preferredLanguages.first?.hasPrefix("ko") ?? false
        let directTitle = isKorean ? "다운로드 폴더에 이미지 저장" : "Save Image to Downloads"
        let saveAsTitle = isKorean ? "이미지를 다른 이름으로 저장..." : "Save Image As..."
        let copyAddressTitle = isKorean ? "이미지 주소 복사" : "Copy Image Address"
        let copyImageTitle = isKorean ? "이미지 복사" : "Copy Image"

        let menu = NSMenu()

        let directItem = NSMenuItem(title: directTitle, action: #selector(self.customSaveImageDirectAction(_:)), keyEquivalent: "")
        directItem.target = self
        directItem.representedObject = imageUrl
        menu.addItem(directItem)

        let saveAsItem = NSMenuItem(title: saveAsTitle, action: #selector(self.customSaveImageAction(_:)), keyEquivalent: "")
        saveAsItem.target = self
        saveAsItem.representedObject = imageUrl
        menu.addItem(saveAsItem)

        menu.addItem(NSMenuItem.separator())

        let copyAddressItem = NSMenuItem(title: copyAddressTitle, action: #selector(self.copyImageAddressAction(_:)), keyEquivalent: "")
        copyAddressItem.target = self
        copyAddressItem.representedObject = imageUrl
        menu.addItem(copyAddressItem)

        let copyImageItem = NSMenuItem(title: copyImageTitle, action: #selector(self.copyImageAction(_:)), keyEquivalent: "")
        copyImageItem.target = self
        copyImageItem.representedObject = imageUrl
        menu.addItem(copyImageItem)

        return menu
    }

    @objc func copyImageAddressAction(_ sender: NSMenuItem) {
        guard let imageUrl = self.imageURL(for: sender) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(imageUrl.absoluteString, forType: .string)
    }

    @objc func copyImageAction(_ sender: NSMenuItem) {
        guard let imageUrl = self.imageURL(for: sender) else { return }
        self.handleCopyImage(url: imageUrl)
    }
}

private extension DeskGPTViewController {
    func imageURL(for sender: NSMenuItem) -> URL? {
        return sender.representedObject as? URL
    }
}
