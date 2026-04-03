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
import FileWatcher

/// 主界面展示模式：渲染预览或编辑源码
enum MarkdownViewMode: String, CaseIterable, Identifiable {
    case preview
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview: return "预览"
        case .edit: return "编辑"
        }
    }
}

class DocumentManager: ObservableObject {
    @Published var fileURL: URL?
    /// 与磁盘上次成功保存或载入一致的内容，用于判断是否有未保存修改
    private var lastSavedContent: String = ""

    @Published var content: String = "" {
        didSet {
            updateStats()
            isDirty = content != lastSavedContent
        }
    }

    /// 是否存在未写入磁盘的修改
    @Published private(set) var isDirty: Bool = false

    /// 预览 / 编辑
    @Published var viewMode: MarkdownViewMode = .preview
    @Published var scrollPosition: CGFloat = 0
    @Published var scrollProgress: CGFloat = 0  // 0.0 - 1.0
    @Published var tocItems: [TOCItem] = []
    @Published var currentHeadingSlug: String = ""
    @Published var showTOC: Bool = true

    /// 渲染状态：用于淡入动画
    @Published var isRendered: Bool = false

    // 文档统计
    @Published var charCount: Int = 0
    @Published var lineCount: Int = 0
    @Published var wordCount: Int = 0

    /// WebView 引用
    weak var webView: WKWebView?

    private var fileWatcher: FileWatcher?

    deinit {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// 初始化并打开文件
    init(fileURL: URL? = nil) {
        if let url = fileURL {
            openFile(url)
        }
    }

    /// 打开文件
    func openFile(_ url: URL) {
        let resolved = url.standardizedFileURL
        stopFileWatcher()
        fileURL = resolved
        let loaded = loadContent(from: resolved)
        lastSavedContent = loaded
        content = loaded
        scrollPosition = 0
        currentHeadingSlug = ""
        tocItems = []
        isRendered = false  // 重置渲染状态，触发淡入动画
        viewMode = .preview
        startFileWatcher(for: resolved)
    }

    /// 将当前内容写入磁盘；成功时清除脏标记
    @discardableResult
    func saveToDisk() -> Bool {
        guard let url = fileURL else { return false }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            lastSavedContent = content
            isDirty = false
            return true
        } catch {
            return false
        }
    }

    /// 从编辑切回预览时调用：在未修改时合并外部保存的磁盘内容
    func syncFromDiskIfCleanPreservingScroll() {
        guard viewMode == .preview, !isDirty, let url = fileURL else { return }

        let apply: (CGFloat) -> Void = { [weak self] scrollY in
            guard let self = self else { return }
            let disk = self.loadContent(from: url)
            guard disk != self.content else { return }
            self.scrollPosition = scrollY
            self.lastSavedContent = disk
            self.content = disk
        }

        if let wv = webView {
            wv.evaluateJavaScript("window.pageYOffset") { result, _ in
                let y: CGFloat
                if let n = result as? NSNumber {
                    y = CGFloat(n.doubleValue)
                } else if let c = result as? CGFloat {
                    y = c
                } else {
                    y = 0
                }
                DispatchQueue.main.async {
                    apply(y)
                }
            }
        } else {
            apply(0)
        }
    }

    /// 标记渲染完成
    func markRendered() {
        isRendered = true
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

    private func stopFileWatcher() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    private func startFileWatcher(for url: URL) {
        let path = url.path
        let watcher = FileWatcher(url: url) { [weak self] in
            self?.reloadFromDiskIfChanged(watchedPath: path)
        }
        fileWatcher = watcher
        watcher.start()
    }

    /// 外部工具保存文件后重新载入并触发 WebView 渲染；尽量保持滚动位置。
    private func reloadFromDiskIfChanged(watchedPath: String) {
        guard let url = fileURL, url.path == watchedPath else { return }
        // 编辑模式下不自动覆盖缓冲区；有未保存修改时也不覆盖
        guard viewMode == .preview, !isDirty else { return }

        let apply: (CGFloat) -> Void = { [weak self] scrollY in
            guard let self = self else { return }
            let newContent = self.loadContent(from: url)
            guard newContent != self.content else { return }
            self.scrollPosition = scrollY
            self.lastSavedContent = newContent
            self.content = newContent
        }

        if let wv = webView {
            wv.evaluateJavaScript("window.pageYOffset") { result, _ in
                let y: CGFloat
                if let n = result as? NSNumber {
                    y = CGFloat(n.doubleValue)
                } else if let c = result as? CGFloat {
                    y = c
                } else {
                    y = 0
                }
                DispatchQueue.main.async {
                    apply(y)
                }
            }
        } else {
            apply(0)
        }
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
extension Notification.Name {
    static let mdGlanceSaveDocument = Notification.Name("mdGlanceSaveDocument")
}

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
