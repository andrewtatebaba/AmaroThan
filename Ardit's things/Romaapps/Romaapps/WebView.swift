//
//  WebView.swift
//  Roma test app
//
//  Created by Opre Roma2 on 4. 7. 2025.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = URL(string: "https://apple.com") {
            let request = URLRequest(url: url)
            uiView.load(request) // ✅ use uiView, not webView
        }
    }
}
