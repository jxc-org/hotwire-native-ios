import Foundation
import WebKit

public protocol WKUIControllerDelegate: AnyObject {
    func present(_ alert: UIAlertController, animated: Bool)
    func newWindowRequested(for url: URL)
}

public extension WKUIControllerDelegate {
    func newWindowRequested(for url: URL) {}
}

open class WKUIController: NSObject, WKUIDelegate {
    private weak var delegate: WKUIControllerDelegate?

    public init(delegate: WKUIControllerDelegate!) {
        self.delegate = delegate
    }

    open func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .default) { _ in
            completionHandler()
        })
        delegate?.present(alert, animated: true)
    }

    open func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        delegate?.present(alert, animated: true)
    }
    
    open func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.requestsNewWindow,
              let url = navigationAction.request.url,
              url.isRoutableNewWindowURL else {
            return nil
        }
        delegate?.newWindowRequested(for: url)
        return nil
    }
}

private extension URL {
    var isRoutableNewWindowURL: Bool {
        guard !absoluteString.isEmpty else {
            return false
        }

        switch absoluteString {
        case "about:blank", "about:srcdoc":
            return false
        default:
            return true
        }
    }
}
