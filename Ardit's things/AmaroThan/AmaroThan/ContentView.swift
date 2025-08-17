import SwiftUI

struct ContentView: View {
    var body: some View {
        WebView()
            .ignoresSafeArea(.all, edges: .all)
    }
}

#Preview {
    ContentView()
}
