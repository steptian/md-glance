import Foundation
import WebKit

/// WKURLSchemeHandler 用于从本地 Bundle 提供 JS/CSS/字体等静态资源
/// 约定 URL 形如：mdglance://res/{subpath}
final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
    static let shared = LocalResourceHandler()

    private override init() {
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "mdglance" else {
            let err = makeError(-1, "Invalid URL or scheme")
            NSLog("[LocalResourceHandler] ❌ %@", err.localizedDescription)
            urlSchemeTask.didFailWithError(err)
            return
        }

        let path = url.path
        guard path.hasPrefix("/res/") else {
            let err = makeError(-2, "Unsupported path: \(path)")
            NSLog("[LocalResourceHandler] ❌ %@", err.localizedDescription)
            urlSchemeTask.didFailWithError(err)
            return
        }

        let relativePath = String(path.dropFirst("/res/".count))

        var fileURL = Bundle.module.bundleURL.appendingPathComponent("Resources")
        for component in relativePath.split(separator: "/") {
            fileURL = fileURL.appendingPathComponent(String(component))
        }

        NSLog("[LocalResourceHandler] 📦 bundle=%@ file=%@",
              Bundle.module.bundleURL.path, fileURL.path)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let err = makeError(-3, "File not found: \(fileURL.path)")
            NSLog("[LocalResourceHandler] ❌ %@", err.localizedDescription)
            urlSchemeTask.didFailWithError(err)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = Self.mimeType(for: fileURL.pathExtension)
            NSLog("[LocalResourceHandler] ✅ %@ (%d bytes, %@)", relativePath, data.count, mimeType)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType,
                    "Cache-Control": "max-age=31536000"
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            NSLog("[LocalResourceHandler] ❌ read error: %@", error.localizedDescription)
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "LocalResourceHandler", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "js":    return "application/javascript"
        case "css":   return "text/css"
        case "woff2": return "font/woff2"
        case "woff":  return "font/woff"
        case "ttf":   return "font/ttf"
        case "svg":   return "image/svg+xml"
        case "png":   return "image/png"
        default:      return "application/octet-stream"
        }
    }
}
