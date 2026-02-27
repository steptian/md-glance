//
//  QuickLookViewController.swift
//  md-glanceQuickLook
//
//  QuickLook 预览视图控制器
//

import Cocoa
import WebKit
import md_glanceCore

/// QuickLook 预览视图控制器
/// 使用 WKWebView 渲染 Markdown 内容
class QuickLookViewController: NSViewController {

    private var webView: WKWebView?
    private var content: String = ""

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 创建 WebView
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        view.addSubview(webView)
        self.webView = webView
    }

    /// 设置 Markdown 内容
    func setContent(_ markdown: String) {
        self.content = markdown
        renderContent()
    }

    private func renderContent() {
        guard let webView = webView else { return }

        let renderer = MarkdownRenderer()
        let html = renderer.render(markdown: content)

        webView.loadHTMLString(html, baseURL: nil)
    }
}
