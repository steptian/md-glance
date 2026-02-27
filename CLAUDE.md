# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

md-glance 是一款 macOS 原生 Markdown 预览工具，专注于"预览"单一功能，不提供编辑能力。

## 技术栈

| 维度 | 方案 |
|:---|:---|
| 开发语言 | Swift |
| UI 框架 | SwiftUI |
| Markdown 渲染 | Ink (自定义 Modifier) + WKWebView |
| 数学公式 | KaTeX (JS) |
| 图表 | Mermaid (JS) |
| 代码高亮 | highlight.js / Prism (JS) |
| 文件监控 | DispatchSource + FSEvents 兜底 |

## 构建命令

```bash
# 构建
xcodebuild -scheme md-glance -configuration Debug build

# 运行测试
xcodebuild test -scheme md-glance -destination 'platform=macOS'

# 发布构建
xcodebuild -scheme md-glance -configuration Release -archivePath build/md-glance.xcarchive archive
```

## 架构要点

### 渲染流程
Markdown → preprocessMath (多行 $$ 块转 HTML) → Ink 解析 + 自定义 Modifier → HTML → WKWebView 渲染

自定义 Modifier：
- MermaidModifier: ```mermaid 代码块 → `<div class="mermaid">`
- MathModifier: $/$$ 公式 → `<span class="math-inline/display">`
- HeadingModifier: `<h*>` → 注入 id 属性，收集 TOC 目录

前端 JS 仅负责渲染预标记元素（KaTeX/Mermaid/highlight.js），不再做 DOM 结构变换。

### 文件监控
使用 DispatchSource 监控文件描述符变更，配合 FSEvents 处理"删除后重建"等编辑器保存行为。

### 资源路径
相对路径资源以 Markdown 文件所在目录为基准解析，通过 `loadHTMLString(_:baseURL:)` 设置 baseURL。

## 功能边界

**包含**：文件读取、内容渲染（GFM/LaTeX/Mermaid）、实时刷新、滚动保持、QuickLook 扩展

**不包含**：文本编辑、文件导出、云同步、多标签页、自定义主题

## 目标平台

- macOS 12.0 (Monterey) 及以上
- 支持 Intel (x86_64) 和 Apple Silicon (arm64)
