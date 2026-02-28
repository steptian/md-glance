//
//  MarkdownRenderer.swift
//  md-glanceCore
//
//  Markdown 渲染器 —— 基于 Ink + 自定义 Modifier
//
//  渲染流程：
//    Markdown 原文
//      → preprocessMath()        将多行 $$ 块转为 HTML div（利用 Ink HTML 透传）
//      → Ink MarkdownParser      解析标准 Markdown
//        ├ MermaidModifier        ```mermaid → <div class="mermaid">
//        ├ MathModifier           $/$$ → <span class="math-inline/display">
//        └ HeadingModifier        <h*> → 注入 id，收集 TOC
//      → wrapInTemplate()        组装完整 HTML 页面
//

import Foundation
import Ink

public final class MarkdownRenderer {

    private let slugTracker = SlugTracker()

    public init() {}

    /// 目录项列表（每次 render 后更新）
    public private(set) var tocItems: [TOCItem] = []

    // MARK: - Public API

    /// 将 Markdown 转换为完整 HTML 页面
    public func render(markdown: String) -> String {
        tocItems = []
        slugTracker.reset()

        let preprocessed = preprocessMath(markdown)

        var parser = MarkdownParser()

        parser.addModifier(makeMermaidModifier())

        for target: Modifier.Target in [.paragraphs, .lists, .blockquotes, .tables] {
            parser.addModifier(makeMathModifier(for: target))
        }

        parser.addModifier(makeHeadingModifier(
            tocCollector: { [weak self] item in self?.tocItems.append(item) },
            slugTracker: slugTracker
        ))

        let htmlContent = parser.html(from: preprocessed)
        return wrapInTemplate(html: htmlContent)
    }

    /// 获取目录
    public func getTOC() -> [TOCItem] {
        tocItems
    }

    // MARK: - Math Pre-processing

    /// 将数学公式提前转为 HTML，利用 Ink 对原始 HTML 的透传能力直接输出。
    ///
    /// - 块级 $$...$$：转为 <div class="math-display">
    /// - 行内 $...$：转为 <span class="math-inline">
    ///
    /// 关键：行内公式中的 `\` 必须替换为 HTML 实体 `&#92;`。
    /// 原因：Ink 会把 `\P`、`\m` 等当作 Markdown 转义字符剥掉反斜杠，
    /// 而 `&#92;` 不是反斜杠字符，Ink 不会处理它；
    /// 前端 KaTeX 通过 el.textContent 读取时，浏览器会自动把 `&#92;` 解码回 `\`。
    public func preprocessMath(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var result: [String] = []
        var mathBuffer: [String] = []
        var inCodeBlock = false
        var collectingMath = false
        var blockquotePrefix = ""

        for line in lines {
            // 引用行前缀 "> " 剥掉后参与公式检测，输出时再补回
            let (content, prefix): (String, String) = {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix(">") else { return (line, "") }
                let rest = String(t[t.index(after: t.startIndex)...]).trimmingCharacters(in: .whitespaces)
                return (rest, "> ")
            }()
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            // 凡是以 ``` 开头的行（含前导空格）都视为围栏边界，输出时去掉前导空格以便 Ink 正确配对
            let isFenceLine = trimmed.hasPrefix("```")

            if isFenceLine {
                if inCodeBlock { inCodeBlock = false } else { inCodeBlock = true }
                if collectingMath {
                    result.append(blockquotePrefix + "$$")
                    result.append(contentsOf: mathBuffer.map { blockquotePrefix + $0 })
                    mathBuffer = []
                    collectingMath = false
                }
                result.append(prefix + trimmed)
                continue
            }

            if inCodeBlock {
                result.append(prefix + content)
                continue
            }

            // 单行块级公式 $$...$$（含引用块内）
            if !collectingMath, let singleLineBlock = Self.replaceSingleLineBlockMath(content) {
                result.append(prefix + singleLineBlock)
                continue
            }

            // 独立 $$ 行：块级公式开始/结束
            if trimmed == "$$" {
                if collectingMath {
                    let formula = mathBuffer.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(blockquotePrefix + "<div class=\"math-display\">\(escapeHTML(formula))</div>")
                    mathBuffer = []
                    collectingMath = false
                } else {
                    blockquotePrefix = prefix
                    collectingMath = true
                }
                continue
            }

            if collectingMath {
                // 若本行是单行 $$...$$，只收集公式部分，避免 buffer 里带 $$ 定界符
                if content.hasPrefix("$$"), let close = content.dropFirst(2).range(of: "$$") {
                    let formula = String(content[content.index(content.startIndex, offsetBy: 2)..<close.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    mathBuffer.append(formula)
                } else {
                    mathBuffer.append(content)
                }
            } else {
                // 兼容非标准写法：行首 4 空格不当作缩进代码块，用 U+00A0 替换避免 Ink 整段解析为 pre
                var normalized = Self.disableIndentedCodeBlock(content)

                // 修复：转义行内的 HTML 标签，避免 Ink 误解析
                // 场景：列表项中包含 ```mermaid 描述，后面跟着 HTML 标签
                // 例如："- MermaidModifier: ```mermaid 代码块 → `<div class=\"mermaid\">`"
                // Ink 会把 <div> 当作原始 HTML 块级元素，导致后续内容被吸入
                normalized = Self.escapeInlineHTMLTags(normalized)

                result.append(prefix + Self.preprocessInlineMath(normalized))
            }
        }

        if collectingMath {
            result.append(blockquotePrefix + "$$")
            result.append(contentsOf: mathBuffer.map { blockquotePrefix + $0 })
        }

        return result.joined(separator: "\n")
    }

    /// 将行首的普通空格 (U+0020) 替换为不中断空格 (U+00A0)，避免被 Ink 解析为缩进代码块。
    /// 这样带 4 空格缩进的内容（如示例、表格）会按普通段落/列表等渲染，兼容非标准写法。
    private static func disableIndentedCodeBlock(_ line: String) -> String {
        let space: Character = " "
        let nbsp = Character(Unicode.Scalar(0x00A0)!)
        guard let firstNonSpace = line.firstIndex(where: { $0 != space }) else {
            return line
        }
        let leadingCount = line.distance(from: line.startIndex, to: firstNonSpace)
        guard leadingCount > 0 else { return line }
        return String(repeating: nbsp, count: leadingCount) + line[firstNonSpace...]
    }

    /// 转义行内的代码围栏和 HTML 标签，避免 Ink 误解析。
    ///
    /// 问题场景：当一行中包含 ```mermaid 描述（非代码块开始），
    /// 1. Ink 会把 ``` 中的反引号当作内联代码标记
    /// 2. Ink 会把后面的 HTML 标签当作原始 HTML 块级元素
    ///
    /// 解决方案：检测这种模式，将行内的 ``` 和 HTML 标签转义为 HTML 实体。
    private static func escapeInlineHTMLTags(_ line: String) -> String {
        // 检测是否包含 ``` 但不是以 ``` 开头（说明是行内描述，不是代码块开始）
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("```") && !trimmed.hasPrefix("```") else {
            return line
        }

        // 转义行内的 ``` 为 &#96;&#96;&#96;（反引号的 HTML 实体）
        // 这样 Ink 就不会把它当作代码围栏或内联代码标记
        var result = line.replacingOccurrences(of: "```", with: "&#96;&#96;&#96;")

        // 检测是否包含可能被误解析的 HTML 标签
        let blockTags = ["<div", "<span", "<p>", "</p>", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6"]
        var hasBlockTag = false
        for tag in blockTags {
            if result.contains(tag) {
                hasBlockTag = true
                break
            }
        }

        guard hasBlockTag else { return result }

        // 转义行内的 HTML 标签
        guard let regex = try? NSRegularExpression(
            pattern: #"</?[a-zA-Z][a-zA-Z0-9]*[^>]*>"#,
            options: []
        ) else { return result }

        let range = NSRange(result.startIndex..., in: result)
        var finalResult = result
        var offset = 0

        regex.enumerateMatches(in: result, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            let matchRange = match.range
            guard let swiftRange = Range(matchRange, in: finalResult) else { return }

            let original = String(finalResult[swiftRange])
            let shouldEscape = blockTags.contains { original.lowercased().hasPrefix($0.lowercased()) }

            if shouldEscape {
                let escaped = original
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")

                let adjustedRange = NSRange(
                    location: matchRange.location + offset,
                    length: matchRange.length
                )
                if let adjustedSwiftRange = Range(adjustedRange, in: finalResult) {
                    finalResult.replaceSubrange(adjustedSwiftRange, with: escaped)
                    offset += escaped.count - original.count
                }
            }
        }

        return finalResult
    }

    /// 单行内的 $$...$$ 替换为 <div class="math-display">，未匹配则返回 nil
    private static func replaceSingleLineBlockMath(_ line: String) -> String? {
        guard let open = line.range(of: "$$"),
              let close = line[open.upperBound...].range(of: "$$")
        else { return nil }
        let formula = String(line[open.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let div = "<div class=\"math-display\">\(escapeHTML(formula))</div>"
        var result = line
        result.replaceSubrange(open.lowerBound..<close.upperBound, with: div)
        return result
    }

    /// 将一行中的 $...$ 替换为 <span class="math-inline">，
    /// 并把 `\` 转为 `&#92;` 以防 Ink 的 Markdown 转义处理剥离反斜杠。
    private static func preprocessInlineMath(_ line: String) -> String {
        guard line.contains("$"),
              let regex = try? NSRegularExpression(
                  pattern: #"(?<!\$)\$([^\$\n]+?)\$(?!\$)"#
              )
        else { return line }

        let nsRange = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: nsRange)
        guard !matches.isEmpty else { return line }

        var result = ""
        var lastEnd = line.startIndex

        for match in matches {
            guard let matchRange   = Range(match.range,       in: line),
                  let contentRange = Range(match.range(at: 1), in: line)
            else { continue }

            result += line[lastEnd..<matchRange.lowerBound]

            let content = String(line[contentRange])

            // 先转义 HTML 特殊字符（& < > " '），最后把 \ 转为 &#92;
            // 顺序很重要：& 必须最先处理，避免把后续引入的 &amp; 里的 & 再次转义
            let safe = content
                .replacingOccurrences(of: "&",  with: "&amp;")
                .replacingOccurrences(of: "<",  with: "&lt;")
                .replacingOccurrences(of: ">",  with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "\\", with: "&#92;")

            result += "<span class=\"math-inline\">\(safe)</span>"
            lastEnd = matchRange.upperBound
        }

        result += line[lastEnd...]
        return result
    }

    // MARK: - HTML Template

    private func wrapInTemplate(html: String) -> String {
        // 检测内容类型，决定是否需要加载特定库
        let hasMath = html.contains("math-display") || html.contains("math-inline")
        let hasMermaid = html.contains("class=\"mermaid\"")

        // 预加载关键资源（优先级最高）
        let preloadHighlightJS = "<link rel=\"preload\" href=\"js/highlight.min.js\" as=\"script\">\n"
        let preloadKatex = hasMath ? "<link rel=\"preload\" href=\"js/katex.min.js\" as=\"script\">\n<link rel=\"preload\" href=\"css/katex.min.css\" as=\"style\">\n" : ""
        let preloadMermaid = hasMermaid ? "<link rel=\"preload\" href=\"js/mermaid.min.js\" as=\"script\">\n" : ""

        // 按需加载的库（同步加载，确保顺序正确）
        let katexCSS = hasMath ? "<link rel=\"stylesheet\" href=\"css/katex.min.css\">\n" : ""
        let katexJS = hasMath ? "<script src=\"js/katex.min.js\"></script>\n" : ""
        let mermaidJS = hasMermaid ? "<script src=\"js/mermaid.min.js\"></script>" : ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Markdown Preview</title>

            <!-- 预加载关键资源 -->
            \(preloadHighlightJS)\(preloadKatex)\(preloadMermaid)

            <style>
                \(Self.inlineCSS)
            </style>

            <!-- highlight.js (始终加载) -->
            <link rel="stylesheet" href="css/github.min.css">
            <script src="js/highlight.min.js"></script>

            \(katexCSS)
        </head>
        <body>
            <div id="skeleton" class="skeleton">
                <div class="sk-title"></div>
                <div class="sk-line w80"></div>
                <div class="sk-line w60"></div>
                <div class="sk-line w90"></div>
                <div class="sk-gap"></div>
                <div class="sk-block"></div>
                <div class="sk-line w70"></div>
                <div class="sk-line w50"></div>
                <div class="sk-gap"></div>
                <div class="sk-block short"></div>
            </div>
            <article class="markdown-body">
                \(html)
            </article>
            \(katexJS)\(mermaidJS)
            <script>
                \(Self.initJS)
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Static Assets

    /// 内联 CSS 样式（GitHub Markdown 风格 + 深色模式）
    static let inlineCSS: String = """
        html, body { margin: 0; padding: 0; height: 100%; background-color: transparent; }

        .markdown-body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.7;
            word-wrap: break-word;
            padding: 32px 40px;
            max-width: 920px;
            margin: 0 auto;
            color: #24292f;
            -webkit-font-smoothing: antialiased;
        }
        .markdown-body h1, .markdown-body h2, .markdown-body h3,
        .markdown-body h4, .markdown-body h5, .markdown-body h6 {
            margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25;
        }
        .markdown-body h1 { font-size: 2em;   border-bottom: 1px solid #d0d7de; padding-bottom: .3em; }
        .markdown-body h2 { font-size: 1.5em; border-bottom: 1px solid #d0d7de; padding-bottom: .3em; }
        .markdown-body h3 { font-size: 1.25em; }
        .markdown-body h4 { font-size: 1em; }
        .markdown-body p  { margin-top: 0; margin-bottom: 16px; }
        .markdown-body code {
            padding: .2em .4em; margin: 0; font-size: 85%;
            background-color: rgba(175,184,193,0.2); border-radius: 6px;
        }
        .markdown-body pre {
            position: relative;
            padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45;
            background-color: #f6f8fa; border-radius: 6px;
        }
        .markdown-body pre code { background-color: transparent; padding: 0; font-size: 100%; counter-reset: line; }
        .markdown-body blockquote {
            padding: 0 1em; color: #57606a;
            border-left: .25em solid #d0d7de; margin: 0 0 16px 0;
        }
        .markdown-body a { color: #0969da; text-decoration: none; }
        .markdown-body a:hover { text-decoration: underline; }
        .markdown-body ul, .markdown-body ol { padding-left: 2em; margin-top: 0; margin-bottom: 16px; }
        .markdown-body li { margin-top: .25em; }
        .markdown-body img { max-width: 100%; box-sizing: content-box; background-color: #fff; }
        .markdown-body table {
            border-spacing: 0; border-collapse: collapse;
            display: block; width: max-content; max-width: 100%; margin-bottom: 16px;
        }
        .markdown-body table th, .markdown-body table td { padding: 6px 13px; border: 1px solid #d0d7de; }
        .markdown-body table th { font-weight: 600; background-color: #f6f8fa; }
        .markdown-body table tr:nth-child(2n) { background-color: #f6f8fa; }
        .markdown-body hr {
            height: .25em; padding: 0; margin: 24px 0;
            background-color: #d0d7de; border: 0;
        }

        /* highlight.js */
        .hljs { background: transparent; padding: 0; }

        /* 代码块工具栏 */
        .code-toolbar {
            position: absolute;
            top: 6px;
            right: 8px;
            display: flex;
            gap: 4px;
            opacity: 0;
            transition: opacity 0.15s ease-in-out;
        }
        .markdown-body pre:hover .code-toolbar {
            opacity: 1;
        }
        .code-btn {
            width: 18px;
            height: 18px;
            border-radius: 4px;
            border: none;
            background-color: rgba(0,0,0,0.04);
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            padding: 0;
        }
        .code-btn svg {
            width: 12px;
            height: 12px;
        }
        .code-btn:active {
            transform: scale(0.95);
        }

        /* Mermaid 图表 */
        .mermaid { text-align: center; margin: 16px 0; }

        /* KaTeX 公式 */
        .math-display { display: block; text-align: center; margin: 1em 0; overflow-x: auto; overflow-y: hidden; }
        .math-display::-webkit-scrollbar { height: 6px; }
        .math-inline  { /* KaTeX 渲染后自带 inline 样式 */ }
        .katex-display { margin: 1em 0; overflow-x: auto; overflow-y: hidden; }
        .katex-display::-webkit-scrollbar { height: 6px; }

        /* 骨架屏：fixed 覆盖，不影响文档流；3 秒后 CSS 兜底淡出 */
        #skeleton {
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            z-index: 999;
            overflow: auto;
            background-color: #ffffff;
            animation: sk-autohide 0.3s ease-out 3s both;
        }
        @keyframes sk-autohide { to { opacity: 0; pointer-events: none; } }

        .skeleton {
            max-width: 920px;
            margin: 32px auto;
            padding: 0 40px;
        }
        .skeleton .sk-title {
            height: 24px;
            margin-bottom: 16px;
            border-radius: 6px;
            background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
            background-size: 200% 100%;
            animation: sk-shimmer 1.5s infinite;
        }
        .skeleton .sk-line {
            height: 12px;
            margin-bottom: 10px;
            border-radius: 6px;
            background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
            background-size: 200% 100%;
            animation: sk-shimmer 1.5s infinite;
        }
        .skeleton .sk-line.w80 { width: 80%; }
        .skeleton .sk-line.w60 { width: 60%; }
        .skeleton .sk-line.w90 { width: 90%; }
        .skeleton .sk-gap { height: 8px; }
        .skeleton .sk-block {
            height: 120px;
            border-radius: 8px;
            margin: 8px 0 16px;
            background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
            background-size: 200% 100%;
            animation: sk-shimmer 1.5s infinite;
        }
        .skeleton .sk-block.short {
            height: 80px;
            width: 70%;
        }

        @keyframes sk-shimmer {
            0% { background-position: -200% 0; }
            100% { background-position: 200% 0; }
        }

        /* 深色模式 */
        @media (prefers-color-scheme: dark) {
            .markdown-body { color: #e6edf3; }
            .markdown-body h1, .markdown-body h2 { border-bottom-color: #30363d; }
            .markdown-body code { background-color: rgba(110,118,129,0.25); }
            .markdown-body pre  { background-color: #161b22; }
            .markdown-body blockquote { color: #8b949e; border-left-color: #3b82f6; }
            .markdown-body a { color: #58a6ff; }
            .markdown-body table th, .markdown-body table td { border-color: #30363d; }
            .markdown-body table th, .markdown-body table tr:nth-child(2n) { background-color: #161b22; }
            .markdown-body hr { background-color: #30363d; }
            #skeleton { background-color: #0d1117; }
            .skeleton .sk-title,
            .skeleton .sk-line,
            .skeleton .sk-block {
                background: linear-gradient(90deg, #20242d 25%, #2b3240 50%, #20242d 75%);
            }
        }
    """

    /// 前端初始化脚本 —— 优化加载速度
    /// 1. 异步加载 JS 库（async）
    /// 2. 代码高亮完成后立即淡出骨架屏
    /// 3. KaTeX 和 Mermaid 并行渲染
    static let initJS: String = """
    (function() {
        'use strict';

        // ── 通用工具：等待库加载 ───────────────────────────────────────
        function waitForLib(name, timeout) {
            return new Promise(function(resolve) {
                if (typeof window[name] !== 'undefined') {
                    resolve(true);
                    return;
                }
                var elapsed = 0;
                var interval = setInterval(function() {
                    if (typeof window[name] !== 'undefined') {
                        clearInterval(interval);
                        resolve(true);
                    } else if ((elapsed += 50) > (timeout || 3000)) {
                        clearInterval(interval);
                        resolve(false);
                    }
                }, 50);
            });
        }

        // ── 代码高亮（快速，优先执行）────────────────────────────────
        async function initHighlightJS() {
            var loaded = await waitForLib('hljs', 2000);
            if (loaded) {
                document.querySelectorAll('pre code').forEach(function(block) {
                    hljs.highlightElement(block);
                });
            }
            enhanceCodeBlocks();
            // 代码高亮完成后立即淡出骨架屏
            fadeOutSkeleton();
        }

        // ── 代码块工具栏 ─────────────────────────────────────────────
        function enhanceCodeBlocks() {
            document.querySelectorAll('.markdown-body pre').forEach(function(pre) {
                try {
                    var code = pre.querySelector('code');
                    if (!code) return;

                    var toolbar = document.createElement('div');
                    toolbar.className = 'code-toolbar';

                    function makeBtn(d, title) {
                        var b = document.createElement('button');
                        b.className = 'code-btn'; b.type = 'button'; b.title = title;
                        b.innerHTML = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="' + d + '"/></svg>';
                        return b;
                    }

                    var copyBtn = makeBtn('M4 2h7a1 1 0 0 1 1 1v9H4V2zm-1 1v10h8v1H3a1 1 0 0 1-1-1V3h1z', '复制代码');
                    copyBtn.addEventListener('click', function(e) {
                        e.stopPropagation();
                        var text = code.textContent;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdGlanceCopy) {
                            window.webkit.messageHandlers.mdGlanceCopy.postMessage({ text: text });
                        } else if (navigator.clipboard) {
                            navigator.clipboard.writeText(text).catch(function(){});
                        }
                    });

                    var lineCount = (code.textContent || '').split('\\n').length;
                    var foldBtn = makeBtn('M8 3L3 8h3v5h4V8h3L8 3zm0 9.5L5 9h2V4h2v5h2l-3 3.5z', '折叠/展开');
                    var isFolded = false;
                    foldBtn.addEventListener('click', function(e) {
                        e.stopPropagation();
                        isFolded = !isFolded;
                        pre.style.maxHeight = isFolded ? '6em' : '';
                        pre.style.overflow  = isFolded ? 'hidden' : 'auto';
                    });

                    toolbar.appendChild(copyBtn);
                    if (lineCount > 10) toolbar.appendChild(foldBtn);
                    pre.appendChild(toolbar);
                } catch(err) {}
            });
        }

        // ── KaTeX 渲染（返回 Promise）────────────────────────────────
        async function initKaTeX() {
            var mathDisplay = document.querySelectorAll('.math-display');
            var mathInline = document.querySelectorAll('.math-inline');
            if (!mathDisplay.length && !mathInline.length) return;

            var loaded = await waitForLib('katex', 3000);
            if (!loaded) return;

            mathDisplay.forEach(function(el) {
                try {
                    el.innerHTML = katex.renderToString(el.textContent.trim(),
                        { displayMode: true, throwOnError: false });
                } catch(e) {}
            });
            mathInline.forEach(function(el) {
                try {
                    el.innerHTML = katex.renderToString(el.textContent.trim(),
                        { displayMode: false, throwOnError: false });
                } catch(e) {}
            });
        }

        // ── Mermaid 渲染（返回 Promise）────────────────────────────────
        async function initMermaid() {
            var els = document.querySelectorAll('.mermaid');
            console.log('[md-glance] Found', els.length, 'mermaid elements');
            if (!els.length) return;

            console.log('[md-glance] Waiting for mermaid library...');
            var loaded = await waitForLib('mermaid', 5000);
            console.log('[md-glance] Mermaid loaded:', loaded);
            if (!loaded) {
                console.error('[md-glance] Mermaid library failed to load');
                return;
            }

            mermaid.initialize({
                startOnLoad: false,
                theme: 'default',
                securityLevel: 'loose',
                flowchart: { useMaxWidth: true },
                sequence:  { useMaxWidth: true },
                gantt:     { useMaxWidth: true }
            });

            var promises = Array.from(els).map(function(el, idx) {
                return new Promise(function(resolve) {
                    var txt = el.textContent.trim();
                    var id  = 'mermaid-svg-' + idx + '-' + Date.now();
                    mermaid.render(id, txt).then(function(r) {
                        el.innerHTML = r.svg;
                        if (r.bindFunctions) r.bindFunctions(el);
                        el.style.cursor = 'pointer';
                        el.addEventListener('click', function() {
                            var svg = el.querySelector('svg');
                            if (!svg) return;
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdGlanceRenderer) {
                                window.webkit.messageHandlers.mdGlanceRenderer.postMessage({
                                    type: 'mermaidPreview', svg: svg.outerHTML
                                });
                            }
                        });
                        resolve();
                    }).catch(function(e) {
                        el.innerHTML = '<pre style="color:red">Mermaid error: ' + (e.message || e) + '</pre>';
                        resolve();
                    });
                });
            });

            await Promise.all(promises);
        }

        function notifyNative() {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdGlanceRenderer) {
                window.webkit.messageHandlers.mdGlanceRenderer.postMessage({ type: 'renderComplete' });
            }
        }

        // ── 骨架屏淡出 ────────────────────────────────────────────────
        function fadeOutSkeleton() {
            var sk = document.getElementById('skeleton');
            if (!sk || sk.dataset.faded === '1') return;
            sk.dataset.faded = '1';
            sk.style.animation  = 'none';
            sk.style.transition = 'opacity 0.2s';
            sk.style.opacity    = '0';
            setTimeout(function() { if (sk.parentNode) sk.parentNode.removeChild(sk); }, 250);
        }

        // ── 主初始化流程 ──────────────────────────────────────────────
        async function initAll() {
            try {
                // 1. 代码高亮（快速），完成后立即淡出骨架屏
                await initHighlightJS();

                // 2. 并行渲染 KaTeX 和 Mermaid（后台执行）
                Promise.all([initKaTeX(), initMermaid()]).then(function() {
                    notifyNative();
                }).catch(function() {});

            } catch(e) {
                fadeOutSkeleton();
            }

            // 兜底：1秒后强制淡出（减少等待时间）
            setTimeout(fadeOutSkeleton, 500);
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initAll);
        } else {
            initAll();
        }
    })();
    """
}
