//
//  DocumentManager.swift
//  md-glance
//
//  单个文档的状态管理
//

import Foundation
import Combine
import WebKit
import md_glanceCore

class DocumentManager: ObservableObject {
    @Published var fileURL: URL?
    @Published var content: String = "" {
        didSet {
            updateStats()
        }
    }
    @Published var scrollPosition: CGFloat = 0
    @Published var scrollProgress: CGFloat = 0  // 0.0 - 1.0
    @Published var tocItems: [TOCItem] = []
    @Published var currentHeadingSlug: String = ""
    @Published var showTOC: Bool = true

    // 文档统计
    @Published var charCount: Int = 0
    @Published var lineCount: Int = 0
    @Published var wordCount: Int = 0

    /// WebView 引用
    weak var webView: WKWebView?

    /// 初始化并打开文件
    init(fileURL: URL? = nil) {
        if let url = fileURL {
            openFile(url)
        }
    }

    /// 打开文件
    func openFile(_ url: URL) {
        fileURL = url
        content = loadContent(from: url)
        scrollPosition = 0
        currentHeadingSlug = ""
        tocItems = []
    }

    func setWebView(_ webView: WKWebView?) {
        self.webView = webView
    }

    /// 设置渲染器并更新目录
    func setRenderer(_ renderer: MarkdownRenderer) {
        self.tocItems = renderer.getTOC()
    }

    /// 跳转到指定标题
    func scrollToHeading(slug: String) {
        guard let webView = webView else { return }

        let js = """
        (function() {
            var element = document.getElementById('\(slug)');
            if (element) {
                element.scrollIntoView({ behavior: 'smooth', block: 'start' });
                return true;
            }
            return false;
        })();
        """

        webView.evaluateJavaScript(js) { _, _ in }
    }

    /// 更新当前可见的标题
    func updateCurrentHeading() {
        guard let webView = webView, !tocItems.isEmpty else { return }

        let js = """
        (function() {
            var headings = document.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]');
            var scrollTop = window.pageYOffset || document.documentElement.scrollTop;
            var found = null;
            for (var i = headings.length - 1; i >= 0; i--) {
                var heading = headings[i];
                var rect = heading.getBoundingClientRect();
                var absoluteTop = rect.top + scrollTop;
                if (scrollTop >= absoluteTop - 100) {
                    found = heading.id;
                    break;
                }
            }
            return found || '';
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, _ in
            if let slug = result as? String, !slug.isEmpty {
                DispatchQueue.main.async {
                    self?.currentHeadingSlug = slug
                }
            }
        }
    }

    func saveScrollPosition() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript("window.pageYOffset") { [weak self] result, _ in
            if let offset = result as? CGFloat {
                self?.scrollPosition = offset
            }
        }
    }

    func updateScrollProgress() {
        guard let webView = webView else { return }
        let js = """
        (function() {
            var scrollTop = window.pageYOffset || document.documentElement.scrollTop;
            var scrollHeight = document.documentElement.scrollHeight - window.innerHeight;
            if (scrollHeight <= 0) return 0;
            return Math.min(1, Math.max(0, scrollTop / scrollHeight));
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            if let progress = result as? CGFloat {
                DispatchQueue.main.async {
                    self?.scrollProgress = progress
                }
            }
        }
    }

    private func loadContent(from url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "# Error\n\nUnable to load file: \(url.path)"
    }

    private func updateStats() {
        // 字符数（不含空格）
        charCount = content.filter { !$0.isWhitespace }.count

        // 行数
        lineCount = content.components(separatedBy: .newlines).count

        // 词数（支持中英文）
        let chineseChars = content.filter { $0.isChineseCharacter }.count
        let englishWords = content
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0.contains { $0.isLetter } }
            .count
        wordCount = chineseChars + englishWords
    }
}

// MARK: - Character 扩展
extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) ||
               (0x2A700...0x2B73F).contains(scalar.value) ||
               (0x2B740...0x2B81F).contains(scalar.value) ||
               (0x2B820...0x2CEAF).contains(scalar.value)
    }
}
