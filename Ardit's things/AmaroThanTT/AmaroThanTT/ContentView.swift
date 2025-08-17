import SwiftUI
import WebKit
import PhotosUI
import UserNotifications
import Network
import AVFoundation
import SafariServices
import MobileCoreServices

// MARK: - WebViewStore
class WebViewStore: ObservableObject {
    weak var webView: WKWebView?
}

// MARK: - App Entry
@main
struct AmaroThanTTApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 21.0/255.0, green: 6.0/255.0, blue: 16.0/255.0)
                    .ignoresSafeArea()
                ContentView()
            }
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var showImagePicker = false
    @State private var showNotificationPage = false
    @StateObject private var webViewStore = WebViewStore()
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []
    
    var body: some View {
        ZStack {
            WebView(
                showImagePicker: $showImagePicker,
                webViewStore: webViewStore,
                showNotificationPage: $showNotificationPage,
                shareItems: $shareItems,
                showShareSheet: $showShareSheet
            )
            .edgesIgnoringSafeArea(.all)
            .opacity(showNotificationPage ? 0 : 1)
            
            if showNotificationPage {
                NotificationAllowView {
                    requestPermissions {
                        showNotificationPage = false
                        // Load home after permissions
                        if let webView = webViewStore.webView,
                           let url = URL(string: "https://amarothan.com/social/home.php") {
                            webView.load(URLRequest(url: url))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareItems = [] }) {
            ActivityView(activityItems: shareItems)
        }
    }
    
    private func requestPermissions(completion: @escaping () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            PHPhotoLibrary.requestAuthorization { _ in }
            DispatchQueue.main.async { completion() }
        }
    }
}

// MARK: - Notification Prompt View
struct NotificationAllowView: View {
    var onAllow: () -> Void
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 32) {
                ZStack {
                    ForEach(0..<6) { i in
                        Circle()
                            .fill(Color.purple.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .offset(x: animate ? CGFloat(i) * 12 : 0)
                            .scaleEffect(animate ? 1.2 : 1.0)
                            .animation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i) * 0.1), value: animate)
                    }
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(radius: 8)
                }
                Text("Enable Notifications")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Stay up to date with alerts and updates. Tap below to allow notifications.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: { onAllow() }) {
                    Text("Allow Notifications")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .cornerRadius(16)
                        .shadow(radius: 8)
                }
                .padding(.horizontal, 32)
            }
            .padding()
        }
        .onAppear { animate = true }
    }
}

// MARK: - WebView
struct WebView: UIViewRepresentable {
    @Binding var showImagePicker: Bool
    var webViewStore: WebViewStore
    @Binding var showNotificationPage: Bool
    @Binding var shareItems: [Any]
    @Binding var showShareSheet: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            showImagePicker: $showImagePicker,
            webViewStore: webViewStore,
            showNotificationPage: $showNotificationPage,
            shareItems: $shareItems,
            showShareSheet: $showShareSheet
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024,
                                   diskCapacity: 200 * 1024 * 1024,
                                   diskPath: "romaCache")
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let uc = WKUserContentController()

        // Safer viewport injection (do NOT disable zoom — accessibility)
        let jsViewport = """
        (function() {
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0';
          document.head.appendChild(meta);
        })();
        """
        uc.addUserScript(WKUserScript(source: jsViewport, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // Message handlers
        uc.add(context.coordinator, name: "openCamera")
        uc.add(context.coordinator, name: "notifyPermission")
        uc.add(context.coordinator, name: "share")
        uc.add(context.coordinator, name: "openExternal")

        config.userContentController = uc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator

        // Set a custom user agent to identify this as an app (helpful for review)
        webView.customUserAgent = "AmaroThanApp/1.0 (iOS)"

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.webView = webView
        webViewStore.webView = webView
        context.coordinator.startNetworkMonitor()

        if let url = URL(string: "https://amarothan.com/login-welcome.php") {
            let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            webView.load(req)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: Coordinator
    class Coordinator: NSObject,
                       WKUIDelegate,
                       WKNavigationDelegate,
                       WKScriptMessageHandler,
                       PHPickerViewControllerDelegate,
                       UIImagePickerControllerDelegate,
                       UINavigationControllerDelegate {
        weak var webView: WKWebView?
        @Binding var showImagePicker: Bool
        var webViewStore: WebViewStore
        @Binding var showNotificationPage: Bool
        @Binding var shareItems: [Any]
        @Binding var showShareSheet: Bool
        private var monitor: NWPathMonitor?
        
        // For open panel flow
        private var openPanelCompletion: (([URL]?) -> Void)?
        private var imagePickerController: UIImagePickerController?

        init(showImagePicker: Binding<Bool>, webViewStore: WebViewStore, showNotificationPage: Binding<Bool>, shareItems: Binding<[Any]>, showShareSheet: Binding<Bool>) {
            _showImagePicker = showImagePicker
            self.webViewStore = webViewStore
            _showNotificationPage = showNotificationPage
            _shareItems = shareItems
            _showShareSheet = showShareSheet
        }

        func startNetworkMonitor() {
            monitor = NWPathMonitor()
            monitor?.pathUpdateHandler = { path in
                DispatchQueue.main.async {
                    if path.status != .satisfied {
                        self.showOfflineBanner()
                    }
                }
            }
            monitor?.start(queue: .main)
        }

        private func showOfflineBanner() {
            guard let root = topViewController() else { return }
            let banner = UILabel(frame: CGRect(x: 0, y: root.view.safeAreaInsets.top, width: root.view.bounds.width, height: 30))
            banner.text = "⚠️ You're offline — showing cached pages"
            banner.textAlignment = .center
            banner.backgroundColor = .systemYellow
            root.view.addSubview(banner)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { banner.removeFromSuperview() }
        }

        // MARK: WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = "window.__isNativeApp = true; window.__appUserAgent = '\(webView.customUserAgent ?? "AmaroThanApp/1.0")';"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let html = """
            <html><body style='font-family: -apple-system; text-align:center; padding-top:50px;'>
            <h1>You're Offline</h1>
            <p>Please check your internet connection.</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        // Intercept navigation: open external links in Safari and handle special app URLs
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            // Block non-HTTPS (strict)
            if url.scheme?.lowercased() != "https" && url.scheme?.lowercased() != "about" && url.scheme?.lowercased() != "data" {
                decisionHandler(.cancel)
                return
            }

            // If the website requests the special path we use for triggering the native notification prompt:
            if url.absoluteString.contains("social/riderectors/make_app_ready_social.php") {
                DispatchQueue.main.async { self.showNotificationPage = true }
                decisionHandler(.cancel)
                return
            }

            // If the user navigates to a post page, request camera/photo permissions proactively
            if url.path.contains("post.php") || url.absoluteString.contains("/post") {
                DispatchQueue.main.async {
                    self.promptForPhotoPermissionsIfNeeded()
                }
            }

            // External link (different host) -> open in Safari (native)
            if let host = url.host, !host.contains("amarothan.com") {
                DispatchQueue.main.async {
                    self.openExternalURL(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: Prompt for photo/camera permissions with a native rationale
        private func promptForPhotoPermissionsIfNeeded() {
            guard let top = topViewController() else { return }
            let alert = UIAlertController(
                title: "Allow Photo & Camera Access",
                message: "To post photos from your device we need access to your camera and photo library. You will be asked for permission when you try to take or select a photo.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Got it", style: .default, handler: { _ in
                self.requestPhotoAndCameraPermissions {}
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            top.present(alert, animated: true)
        }

        private func requestPhotoAndCameraPermissions(_ completion: @escaping () -> Void) {
            // Request photo library read access
            if #available(iOS 14, *) {
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { completion() }
                    }
                }
            } else {
                PHPhotoLibrary.requestAuthorization { _ in
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { completion() }
                    }
                }
            }
        }

        // MARK: JS Message handler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "notifyPermission":
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        let permission = granted ? "granted" : "denied"
                        let js = "window._notificationPermissionCallback && window._notificationPermissionCallback('\(permission)');"
                        self.webView?.evaluateJavaScript(js, completionHandler: nil)
                    }
                }
            case "openCamera":
                // open the native image picker (camera or library) — this is an explicit web -> native request
                DispatchQueue.main.async {
                    self.presentImageChoiceForWebInput(completion: nil)
                }
            case "share":
                if let body = message.body as? [String:Any] {
                    var items: [Any] = []
                    if let text = body["text"] as? String { items.append(text) }
                    if let urlString = body["url"] as? String, let url = URL(string: urlString) { items.append(url) }
                    DispatchQueue.main.async {
                        self.shareItems = items
                        self.showShareSheet = true
                    }
                } else if let text = message.body as? String {
                    DispatchQueue.main.async {
                        self.shareItems = [text]
                        self.showShareSheet = true
                    }
                }
            case "openExternal":
                if let urlString = message.body as? String, let url = URL(string: urlString) {
                    DispatchQueue.main.async { self.openExternalURL(url) }
                }
            default:
                break
            }
        }

        // MARK: JS alert/confirm/prompt -> present native UIAlertController
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            topViewController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            topViewController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            topViewController()?.present(alert, animated: true)
        }

        // MARK: Handle <input type=file> by presenting native picker and returning file URLs to the webview
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            // Save the completion for later when the picker returns
            self.openPanelCompletion = completionHandler
            presentImageChoiceForWebInput(allowsMultiple: parameters.allowsMultipleSelection)
        }

        private func presentImageChoiceForWebInput(allowsMultiple: Bool = false, completion: (([URL]?) -> Void)? = nil) {
            guard let top = topViewController() else {
                self.openPanelCompletion?(nil)
                return
            }

            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { _ in
                    DispatchQueue.main.async {
                        self.requestPhotoAndCameraPermissions {
                            let picker = UIImagePickerController()
                            picker.sourceType = .camera
                            picker.delegate = self
                            picker.mediaTypes = ["public.image"]
                            self.imagePickerController = picker
                            top.present(picker, animated: true)
                        }
                    }
                })
            }

            // Photo library via PHPicker
            sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                DispatchQueue.main.async {
                    self.requestPhotoAndCameraPermissions {
                        var config = PHPickerConfiguration(photoLibrary: .shared())
                        config.filter = .images
                        config.selectionLimit = allowsMultiple ? 0 : 1
                        let php = PHPickerViewController(configuration: config)
                        php.delegate = self
                        top.present(php, animated: true)
                    }
                }
            })

            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                self.openPanelCompletion?(nil)
                self.openPanelCompletion = nil
            })

            // iPad support
            if let pop = sheet.popoverPresentationController, let v = top.view {
                pop.sourceView = v
                pop.sourceRect = CGRect(x: v.bounds.midX, y: v.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }

            top.present(sheet, animated: true)
        }

        // MARK: PHPicker delegate
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                openPanelCompletion?(nil)
                openPanelCompletion = nil
                return
            }

            // For simplicity handle the first selected image (or map them if selectionLimit >1)
            var urls: [URL] = []
            let group = DispatchGroup()
            for r in results {
                group.enter()
                let provider = r.itemProvider
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { object, error in
                        defer { group.leave() }
                        if let img = object as? UIImage, let url = self.writeImageToTemporaryFile(image: img) {
                            urls.append(url)
                        }
                    }
                } else if let typeId = provider.registeredTypeIdentifiers.first {
                    // fallback: try load file representation
                    provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, error in
                        defer { group.leave() }
                        if let src = url {
                            // copy to tmp
                            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + (src.lastPathComponent))
                            try? FileManager.default.copyItem(at: src, to: dest)
                            urls.append(dest)
                        }
                    }
                } else {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.openPanelCompletion?(urls.isEmpty ? nil : urls)
                self.openPanelCompletion = nil
            }
        }

        // MARK: UIImagePickerController delegate (camera)
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            openPanelCompletion?(nil)
            openPanelCompletion = nil
            imagePickerController = nil
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            imagePickerController = nil
            if let img = info[.originalImage] as? UIImage, let url = writeImageToTemporaryFile(image: img) {
                openPanelCompletion?([url])
            } else {
                openPanelCompletion?(nil)
            }
            openPanelCompletion = nil
        }

        // MARK: Helpers - write UIImage to a temporary file and return URL
        private func writeImageToTemporaryFile(image: UIImage) -> URL? {
            guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return nil }
            let tmpDir = FileManager.default.temporaryDirectory
            let filename = "upload-\(UUID().uuidString).jpg"
            let fileURL = tmpDir.appendingPathComponent(filename)
            do {
                try jpeg.write(to: fileURL, options: .atomic)
                return fileURL
            } catch {
                print("Failed write image to tmp: \(error)")
                return nil
            }
        }

        // MARK: Helpers
        private func openExternalURL(_ url: URL) {
            guard let top = topViewController() else { return }
            let svc = SFSafariViewController(url: url)
            top.present(svc, animated: true)
        }

        private func topViewController() -> UIViewController? {
            // Safe scene-based top VC grab
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .rootViewController?.topMostViewController()
        }

        // If you ever need to perform a native POST while preserving web cookies:
        // You can pull cookies from the webView's cookie store. Example (commented):
        /*
        private func fetchCookiesForDomain(_ domain: String, completion: @escaping ([HTTPCookie]) -> Void) {
            webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let filtered = cookies.filter { $0.domain.contains(domain) }
                completion(filtered)
            }
        }
        */
    }
}

// MARK: - Activity (Share) wrapper
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let av = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return av
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - UIViewController extension to find top-most
extension UIViewController {
    func topMostViewController() -> UIViewController {
        presentedViewController?.topMostViewController() ?? self
    }
}
