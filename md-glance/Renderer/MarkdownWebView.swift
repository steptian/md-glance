//
//  MarkdownWebView.swift
//  md-glance
//
//  Markdown 渲染 WebView - SwiftUI 与 WKWebView 的桥接
//

import SwiftUI
import WebKit
import Quartz
import UniformTypeIdentifiers

/// Markdown 渲染视图
/// 将 Markdown 内容渲染为 HTML 并在 WebView 中显示
public struct MarkdownWebView: NSViewRepresentable {

    /// Markdown 内容
    public let markdown: String

    /// 基础 URL，用于解析相对路径资源（如图片）
    public let baseURL: URL?

    /// WebView 创建回调
    public var onWebViewCreated: ((WKWebView) -> Void)?

    /// 渲染完成回调
    public var onRenderComplete: (() -> Void)?

    /// 滚动回调
    public var onScroll: (() -> Void)?

    /// 渲染器更新回调（用于传递 TOC）
    public var onRendererReady: ((MarkdownRenderer) -> Void)?

    /// 文件拖放回调
    public var onFileDrop: ((URL) -> Void)?

    public init(
        markdown: String,
        baseURL: URL?,
        onWebViewCreated: ((WKWebView) -> Void)? = nil,
        onRenderComplete: (() -> Void)? = nil,
        onScroll: (() -> Void)? = nil,
        onRendererReady: ((MarkdownRenderer) -> Void)? = nil,
        onFileDrop: ((URL) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.baseURL = baseURL
        self.onWebViewCreated = onWebViewCreated
        self.onRenderComplete = onRenderComplete
        self.onScroll = onScroll
        self.onRendererReady = onRendererReady
        self.onFileDrop = onFileDrop
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // 允许访问本地文件
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // 注册自定义本地资源协议 mdglance://
        configuration.setURLSchemeHandler(LocalResourceHandler.shared, forURLScheme: "mdglance")

        // 添加脚本消息处理器
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "mdGlanceRenderer")
        contentController.add(context.coordinator, name: "mdGlanceScroll")
        contentController.add(context.coordinator, name: "mdGlanceCopy")
        configuration.userContentController = contentController

        let webView = DropAwareWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.onFileDrop = onFileDrop

        // 设置透明背景
        webView.setValue(false, forKey: "drawsBackground")

        // 通知 WebView 已创建
        onWebViewCreated?(webView)

        return webView
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onRenderComplete: onRenderComplete, onScroll: onScroll, onRendererReady: onRendererReady)
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        // 保存 WebView 引用到 Coordinator
        context.coordinator.webView = webView

        // 计算内容哈希，避免重复渲染
        let contentHash = markdown.hashValue
        guard contentHash != context.coordinator.lastRenderedHash else {
            return  // 内容未变化，跳过渲染
        }
        context.coordinator.lastRenderedHash = contentHash

        // 使用 Coordinator 中的渲染器来转换 Markdown
        let renderer = context.coordinator.renderer

        // 渲染为 HTML（同时生成 TOC）
        var html = renderer.render(markdown: markdown)

        // 处理本地图片：将相对路径图片转换为 base64
        if let baseURL = baseURL {
            html = embedLocalImages(in: html, baseURL: baseURL)
        }

        // 通知渲染器已准备好（传递 TOC）
        onRendererReady?(renderer)

        // 把 HTML 写入 Resources 目录，用 loadFileURL 加载
        // 这样相对路径的 JS/CSS 资源可以直接被 WKWebView 访问，无需自定义 scheme
        let resourcesURL = Bundle.module.bundleURL.appendingPathComponent("Resources")
        let htmlFileURL = resourcesURL.appendingPathComponent("_preview.html")
        do {
            try html.write(to: htmlFileURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(htmlFileURL, allowingReadAccessTo: resourcesURL)
        } catch {
            // 写文件失败时降级为 loadHTMLString
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    /// 将 HTML 中的本地图片转换为 base64 嵌入
    private func embedLocalImages(in html: String, baseURL: URL) -> String {
        var result = html

        // 匹配 <img src="..."> 标签
        let imgPattern = #"<img[^>]+src="([^"]+)"[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: []) else {
            return html
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches.reversed() {
            guard let srcRange = Range(match.range(at: 1), in: html) else { continue }
            let src = String(html[srcRange])

            if src.contains("://") || src.hasPrefix("data:") { continue }

            let imageURL = baseURL.appendingPathComponent(src)
            guard let imageData = try? Data(contentsOf: imageURL) else { continue }

            // 检测 MIME 类型
            let mimeType: String
            switch imageURL.pathExtension.lowercased() {
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "png":
                mimeType = "image/png"
            case "gif":
                mimeType = "image/gif"
            case "webp":
                mimeType = "image/webp"
            default:
                mimeType = "image/jpeg"
            }

            let base64String = imageData.base64EncodedString()
            let dataURI = "data:\(mimeType);base64,\(base64String)"

            if let fullRange = Range(match.range, in: result) {
                let originalTag = String(result[fullRange])
                let newTag = originalTag.replacingOccurrences(of: "src=\"\(src)\"", with: "src=\"\(dataURI)\"")
                result.replaceSubrange(fullRange, with: newTag)
            }
        }

        return result
    }

    /// Coordinator 处理 WebView 代理事件
    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, QLPreviewPanelDataSource {
        var renderer: MarkdownRenderer
        var onRenderComplete: (() -> Void)?
        var onScroll: (() -> Void)?
        var onRendererReady: ((MarkdownRenderer) -> Void)?
        weak var webView: WKWebView?
        private var scrollObserverAdded = false

        var lastRenderedHash: Int = 0

        init(onRenderComplete: (() -> Void)?, onScroll: (() -> Void)?, onRendererReady: ((MarkdownRenderer) -> Void)?) {
            self.renderer = MarkdownRenderer()
            self.onRenderComplete = onRenderComplete
            self.onScroll = onScroll
            self.onRendererReady = onRendererReady
        }

        // Quick Look 预览
        private var mermaidPreviewURL: URL?

        // MARK: - WKScriptMessageHandler

        /// 接收来自 JavaScript 的消息
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "mdGlanceRenderer":
                if let body = message.body as? [String: Any],
                   let type = body["type"] as? String {
                    if type == "renderComplete" {
                        onRenderComplete?()
                    } else if type == "mermaidPreview",
                              let svg = body["svg"] as? String {
                        handleMermaidPreview(svg: svg)
                    }
                }
            case "mdGlanceScroll":
                onScroll?()
            case "mdGlanceCopy":
                if let body = message.body as? [String: Any],
                   let text = body["text"] as? String {
                    copyToClipboard(text: text)
                }
            default:
                break
            }
        }

        private func copyToClipboard(text: String) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        private func handleMermaidPreview(svg: String) {
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let url = tmpDir.appendingPathComponent("md-glance-mermaid-\(UUID().uuidString).svg")
            do {
                try svg.data(using: .utf8)?.write(to: url)
                mermaidPreviewURL = url
                if let panel = QLPreviewPanel.shared() {
                    panel.dataSource = self
                    panel.makeKeyAndOrderFront(nil)
                }
            } catch {
                // 如果 Quick Look 失败，退化为用默认应用打开
                NSWorkspace.shared.open(url)
            }
        }

        // MARK: - WKNavigationDelegate

        /// 页面加载完成
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 通知渲染完成
            onRenderComplete?()

            // 注入额外的 CSS 以确保透明背景和隐藏滚动条
            let css = """
            (function() {
                document.body.style.backgroundColor = 'transparent';
                var style = document.createElement('style');
                style.textContent = '::-webkit-scrollbar { display: none !important; } html { scrollbar-width: none !important; } body { scrollbar-width: none !important; }';
                document.head.appendChild(style);
            })();
            """
            webView.evaluateJavaScript(css) { _, _ in }

            // 添加滚动监听
            if !scrollObserverAdded {
                let scrollJS = """
                window.addEventListener('scroll', function() {
                    window.webkit.messageHandlers.mdGlanceScroll.postMessage({});
                }, { passive: true });
                """
                webView.evaluateJavaScript(scrollJS) { _, _ in }
                scrollObserverAdded = true
            }
        }

        // MARK: - QLPreviewPanelDataSource

        public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            return mermaidPreviewURL == nil ? 0 : 1
        }

        public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            return mermaidPreviewURL as NSURL?
        }

        /// 处理导航决策 - 外部链接在系统浏览器中打开
        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // 检查是否是链接点击
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    // 跳过锚点链接
                    if url.fragment != nil && url.path.isEmpty {
                        decisionHandler(.allow)
                        return
                    }

                    // 在系统默认浏览器中打开外部链接
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }

            // 检查目标 URL 是否是外部链接
            if let url = navigationAction.request.url, url.host != nil {
                // 如果 URL 有 host 且不是 file:// 协议，认为是外部链接
                if url.scheme != "file" && url.scheme != "about" {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }

            decisionHandler(.allow)
        }

        /// 处理新窗口请求
        public func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // 在系统浏览器中打开
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

/// SwiftUI 视图扩展，用于支持滚动位置保持
extension MarkdownWebView {
    /// 滚动到顶部
    func scrollToTop(in webView: WKWebView) {
        webView.evaluateJavaScript("window.scrollTo(0, 0)")
    }

    /// 获取当前滚动位置
    func getScrollPosition(in webView: WKWebView, completion: @escaping (CGFloat) -> Void) {
        webView.evaluateJavaScript("window.pageYOffset") { result, _ in
            if let offset = result as? CGFloat {
                completion(offset)
            }
        }
    }

    /// 设置滚动位置
    func setScrollPosition(_ position: CGFloat, in webView: WKWebView) {
        webView.evaluateJavaScript("window.scrollTo(0, \(position))")
    }
}

// MARK: - 支持文件拖放的 WebView
class DropAwareWebView: WKWebView {
    var onFileDrop: ((URL) -> Void)?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setupDragging()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDragging()
    }

    private func setupDragging() {
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasMarkdownFile(in: sender) {
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasMarkdownFile(in: sender) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = extractMarkdownFileURL(from: sender) else {
            return false
        }
        onFileDrop?(url)
        return true
    }

    private func hasMarkdownFile(in sender: NSDraggingInfo) -> Bool {
        return extractMarkdownFileURL(from: sender) != nil
    }

    private func extractMarkdownFileURL(from sender: NSDraggingInfo) -> URL? {
        let pasteboard = sender.draggingPasteboard

        // 尝试从文件 URL 读取
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if url.pathExtension == "md" {
                    return url
                }
            }
        }

        return nil
    }
}
