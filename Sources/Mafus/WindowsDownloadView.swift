import SwiftUI
import WebKit

struct WindowsDownloadView: View {
    let architecture: ImageArchitecture
    let onDownload: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var webError: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Windows 11 ISO").font(.headline)
                    Text(L("Выберите выпуск и язык на официальном сайте Microsoft")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Закрыть")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            if let webError { Text(webError).font(.caption).foregroundStyle(.red).padding(12) }
            MicrosoftDownloadPage(architecture: architecture, onDownload: { url in dismiss(); onDownload(url) }, onError: { webError = $0 })
            Divider()
            Label(L("ISO скачивается в Mafus после выбора ссылки Microsoft"), systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).padding(12)
        }.frame(width: 900, height: 700)
    }
}
private struct MicrosoftDownloadPage: NSViewRepresentable {
    let architecture: ImageArchitecture
    let onDownload: (URL) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDownload: onDownload, onError: onError) }
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator
        // A top-level official page retains Microsoft's session and signed-link flow.
        let suffix = architecture == .arm64 ? "windows11arm64" : "windows11"
        web.load(URLRequest(url: URL(string: "https://www.microsoft.com/en-us/software-download/\(suffix)")!))
        return web
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onDownload: (URL) -> Void
        let onError: (String) -> Void
        private var captured = false
        init(onDownload: @escaping (URL) -> Void, onError: @escaping (String) -> Void) { self.onDownload = onDownload; self.onError = onError }
        func capture(_ url: URL?) -> Bool {
            guard let url, url.scheme == "https", let host = url.host?.lowercased(), (host == "microsoft.com" || host.hasSuffix(".microsoft.com")), url.pathExtension.lowercased() == "iso" else { return false }
            if !captured { captured = true; onDownload(url) }
            return true
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if capture(action.request.url) { decisionHandler(.cancel) }
            else if let scheme = action.request.url?.scheme, !["https", "about"].contains(scheme) { decisionHandler(.cancel) }
            else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if capture(response.response.url) { decisionHandler(.cancel) } else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if !capture(action.request.url) && action.targetFrame == nil { webView.load(action.request) }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError("Microsoft: " + error.localizedDescription) }
        }
    }
}
