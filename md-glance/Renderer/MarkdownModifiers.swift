//
//  MarkdownModifiers.swift
//  md-glanceCore
//
//  自定义 Ink Modifier —— 在 Swift 层识别 Mermaid / KaTeX / Heading
//  并输出带有特定标签的 HTML，前端 JS 仅负责渲染。
//

import Foundation
import Ink

// MARK: - Mermaid Code Block Modifier

/// 识别 ```mermaid 代码块，输出 <div class="mermaid"> 替代 <pre><code>
///
/// 代码经过 HTML 实体转义后放入 <div>，浏览器解析时会在 DOM textNode 中
/// 自动解码回原始字符。Mermaid 通过 `el.textContent` 读取，拿到的是正确语法。
/// 如果不转义，`<<abstract>>` 等内容会被 HTML 解析器当成 DOM 标签而丢失。
func makeMermaidModifier() -> Modifier {
    Modifier(target: .codeBlocks) { html, markdown in
        let raw = String(markdown)
        guard raw.hasPrefix("```mermaid") else { return html }

        let lines = raw.components(separatedBy: "\n")
        let code = lines
            .dropFirst()
            .drop(while: { $0.isEmpty })
            .reversed().drop(while: {
                $0.trimmingCharacters(in: .whitespaces) == "```" ||
                $0.trimmingCharacters(in: .whitespaces).isEmpty
            }).reversed()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let escaped = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return "<div class=\"mermaid\">\(escaped)</div>"
    }
}

// MARK: - Math Formula Modifier

/// 处理段落中的行内公式 $...$ 和单行块公式 $$...$$
/// 将其替换为带有 class 的 <span>/<div>，供前端 KaTeX 渲染。
func makeMathModifier(for target: Modifier.Target) -> Modifier {
    Modifier(target: target) { html, _ in
        processMathInHTML(html)
    }
}

/// 在 HTML 片段中替换 $$ / $ 为 KaTeX 占位标签
private func processMathInHTML(_ html: String) -> String {
    var result = html

    // 1. 块级公式 $$...$$ （可能跨行，用 dotMatchesLineSeparators）
    if let blockRegex = try? NSRegularExpression(
        pattern: #"\$\$(.+?)\$\$"#,
        options: [.dotMatchesLineSeparators]
    ) {
        let range = NSRange(result.startIndex..., in: result)
        result = blockRegex.stringByReplacingMatches(
            in: result, range: range,
            withTemplate: #"<span class="math-display">$1</span>"#
        )
    }

    // 2. 行内公式 $...$ （不跨行；用负向前瞻/后顾避免误匹配 $$）
    if let inlineRegex = try? NSRegularExpression(
        pattern: #"(?<!\$)\$([^\$\n]+?)\$(?!\$)"#
    ) {
        let range = NSRange(result.startIndex..., in: result)
        result = inlineRegex.stringByReplacingMatches(
            in: result, range: range,
            withTemplate: #"<span class="math-inline">$1</span>"#
        )
    }

    return result
}

// MARK: - Heading ID Modifier

/// 为 <h1>–<h6> 标签注入 id 属性，使 TOC 锚点跳转生效。
/// 同时将解析到的标题收集到外部 tocCollector 闭包。
func makeHeadingModifier(
    tocCollector: @escaping (TOCItem) -> Void,
    slugTracker: SlugTracker
) -> Modifier {
    Modifier(target: .headings) { html, _ in
        guard let levelChar = html.first(where: { $0.isNumber }),
              let level = Int(String(levelChar)),
              (1...6).contains(level)
        else { return html }

        let title = extractHeadingText(from: html)
        let slug = slugTracker.uniqueSlug(for: title)

        tocCollector(TOCItem(level: level, title: title, slug: slug))

        return insertIdAttribute(into: html, id: slug)
    }
}

// MARK: - Slug Tracker

/// 负责生成唯一的 heading slug（同名标题自动加后缀）
final class SlugTracker {
    private var counts: [String: Int] = [:]

    func reset() { counts.removeAll() }

    func uniqueSlug(for title: String) -> String {
        let base = generateSlug(from: title)
        let count = counts[base, default: 0]
        counts[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }

    private func generateSlug(from title: String) -> String {
        title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

// MARK: - HTML Helpers

func escapeHTML(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

/// 从 <h*>.....</h*> 中提取纯文本标题（去掉内嵌 HTML 标签）
private func extractHeadingText(from html: String) -> String {
    guard let openEnd = html.range(of: ">"),
          let closeStart = html.range(of: "</", options: .backwards)
    else { return "" }

    let inner = String(html[openEnd.upperBound..<closeStart.lowerBound])

    // 去除可能残留的内联 HTML（如 <code>、<em> 等）
    guard let stripRegex = try? NSRegularExpression(pattern: "<[^>]+>") else {
        return inner
    }
    return stripRegex.stringByReplacingMatches(
        in: inner,
        range: NSRange(inner.startIndex..., in: inner),
        withTemplate: ""
    ).trimmingCharacters(in: .whitespaces)
}

/// 在 <h*> 开标签中插入 id="..."
private func insertIdAttribute(into html: String, id: String) -> String {
    guard let tagEnd = html.range(of: ">") else { return html }
    return String(html[html.startIndex..<tagEnd.lowerBound])
        + " id=\"\(id)\""
        + String(html[tagEnd.lowerBound...])
}
