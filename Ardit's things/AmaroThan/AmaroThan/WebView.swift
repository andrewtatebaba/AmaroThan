import SwiftUI
import WebKit
import UniformTypeIdentifiers
import PhotosUI
import UserNotifications
import Network

struct ContentView: View {
    @State private var pickedImage: UIImage?
    @State private var showImagePicker = false

    var body: some View {
        ZStack {
            WebView(showImagePicker: $showImagePicker)
                .edgesIgnoringSafeArea(.all)

            // Optional camera button overlay
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showImagePicker = true }) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                            .padding()
                            .background(Color.white.opacity(0.7))
                            .clipShape(Circle())
                            .padding()
                    }
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            PhotoPicker { results in
                guard let item = results.first,
                      let url = item.itemProvider.registeredTypeIdentifiers.first.flatMap({ UTType($0) }) != nil else {
                    return
                }
                item.itemProvider.loadFileRepresentation(forTypeIdentifier: url.identifier) { url, _ in
                    if let url = url,
                       let data = try? Data(contentsOf: url),
                       let uiImage = UIImage(data: data) {
                        pickedImage = uiImage
                        // TODO: upload uiImage via URLSession here
                    }
                }
            }
        }
    }
}

/// Photo picker for iOS 14+
struct PhotoPicker: UIViewControllerRepresentable {
    var completion: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: ([PHPickerResult]) -> Void
        init(completion: @escaping ([PHPickerResult]) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            completion(results)
        }
    }
}

/// WebView wrapper with offline & native features
struct WebView: UIViewRepresentable {
    @Binding var showImagePicker: Bool

    func makeCoordinator() -> Coordinator { Coordinator(showImagePicker: $showImagePicker) }

    func makeUIView(context: Context) -> WKWebView {
        // Cache setup
        let mem = 50 * 1024 * 1024
        let disk = 200 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, diskPath: "romaCache")

        // WebView config
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let uc = WKUserContentController()
        // Notification bridge
        uc.addUserScript(.init(source: """
            Notification.requestPermission = function() {
              window.webkit.messageHandlers.notifyPermission.postMessage(null);
              return Promise.resolve(Notification.permission);
            };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        uc.add(context.coordinator, name: "notifyPermission")

        // Camera bridge
        uc.addUserScript(.init(source: """
            window.openCamera = function() {
              window.webkit.messageHandlers.openCamera.postMessage(null);
            };
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        uc.add(context.coordinator, name: "openCamera")

        config.userContentController = uc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.startNetworkMonitor()
        load(urlString: "https://yourdomain.com", in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func load(urlString: String, in webView: WKWebView) {
        guard let url = URL(string: urlString) else { return }
        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        webView.load(req)
    }

    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        @Binding var showImagePicker: Bool
        private var monitor: NWPathMonitor?
        @Published var isOnline = true

        init(showImagePicker: Binding<Bool>) {
            _showImagePicker = showImagePicker
        }

        // Network monitoring
        func startNetworkMonitor() {
            monitor = NWPathMonitor()
            monitor?.pathUpdateHandler = { path in
                DispatchQueue.main.async {
                    if self.isOnline && path.status != .satisfied {
                        self.showOfflineBanner()
                    }
                    self.isOnline = (path.status == .satisfied)
                }
            }
            monitor?.start(queue: .main)
        }

        private func showOfflineBanner() {
            guard let root = topViewController() else { return }
            let banner = UILabel(frame: CGRect(x: 0, y: 44, width: root.view.bounds.width, height: 30))
            banner.text = "⚠️ You're offline — showing cached pages"
            banner.textAlignment = .center
            banner.backgroundColor = .systemYellow
            root.view.addSubview(banner)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                banner.removeFromSuperview()
            }
        }

        // Offline fallback
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let html = """
            <html><body style='font-family: -apple-system; text-align:center; padding-top:50px;'>
            <h1>You're Offline</h1>
            <p>Please check your internet connection.</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        // JS Alerts
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            presentAlert(message: message, actions: [
                UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }
            ])
        }

        // Handle JS messages
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "notifyPermission":
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            case "openCamera":
                DispatchQueue.main.async { self.showImagePicker = true }
            default: break
            }
        }

        // Helpers
        private func topViewController() -> UIViewController? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .windows.first?
                .rootViewController
        }

        private func presentAlert(message: String, actions: [UIAlertAction]) {
            guard let root = topViewController() else { return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            actions.forEach { alert.addAction($0) }
            root.present(alert, animated: true)
        }
    }
}
