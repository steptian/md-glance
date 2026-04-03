# md-glance

> 一款简约优雅的 macOS 原生 Markdown 预览工具

<div align="center">

![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue?logo=apple)
![License](https://img.shields.io/badge/license-MIT-green)

[English](#english) | [中文](#中文)

</div>

## ✨ 特性

- **🎨 精美渲染** - GitHub 风格的 Markdown 样式，支持深色模式
- **✏️ 预览与编辑** - 工具栏可在「预览」与「编辑」间切换；编辑模式为等宽源码编辑，支持 **⌘S 保存** 到磁盘，标题显示未保存状态
- **🧮 数学公式** - 基于 KaTeX 的 LaTeX 数学公式渲染
- **📊 图表支持** - Mermaid 流程图、时序图、甘特图等
- **💻 代码高亮** - highlight.js 支持多种编程语言语法高亮
- **📑 目录导航** - 自动生成 TOC 目录，支持快速跳转（预览模式）
- **🔄 实时刷新** - 预览模式下，外部保存文件后自动重新渲染；编辑或未保存时不会覆盖本地修改
- **📜 滚动保持** - 刷新后自动恢复阅读位置
- **🖱️ 拖拽打开** - 支持拖拽 Markdown 文件到窗口
- **🔍 QuickLook** - 按空格键快速预览 Markdown 文件

## 🚀 快速开始

### 下载安装

从 [Releases](https://github.com/steptian/md-glance/releases) 下载最新的 `.dmg` 安装包，双击安装即可。

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/steptian/md-glance.git
cd md-glance

# 构建
swift build

# 运行
swift run md-glance
```

### 构建发布版本

```bash
# 使用提供的构建脚本
./build-dmg.sh
```

构建产物位于 `release/md-glance.dmg`。

## 🛠️ 技术栈

| 维度 | 方案 |
|:---|:---|
| 开发语言 | Swift 5.9 |
| UI 框架 | SwiftUI |
| Markdown 解析 | [Ink](https://github.com/JohnSundell/Ink) |
| 数学公式 | KaTeX |
| 图表 | Mermaid |
| 代码高亮 | highlight.js |
| 文件监控 | DispatchSource + FSEvents |

## 📁 项目结构

```
md-glance/
├── md-glance/
│   ├── App/              # 主应用 UI (SwiftUI)
│   │   ├── ContentView.swift
│   │   └── DocumentManager.swift
│   ├── Renderer/         # Markdown 渲染引擎
│   │   ├── MarkdownRenderer.swift
│   │   └── Resources/    # CSS/JS 资源
│   ├── FileWatcher/      # 文件监控模块
│   └── Resources/        # Info.plist 等
├── md-glanceCLI/         # 命令行工具
│   └── main.swift
├── md-glanceQuickLook/   # QuickLook 扩展
│   └── QuickLookViewController.swift
├── docs/
│   └── spec.md           # 需求规格文档
├── Package.swift
├── CLAUDE.md
└── README.md
```

## 💡 使用方法

### GUI 应用

1. 双击打开 `md-glance.app`
2. 使用 `⌘O` 打开 Markdown 文件，或直接拖拽文件到窗口
3. 使用工具栏 **「预览 | 编辑」** 分段控件切换模式；在编辑模式下修改后可用工具栏保存按钮或 **⌘S** 写入文件
4. 预览模式下可切换目录侧栏、复制全文等

### 命令行工具 (mdg)

```bash
# 安装 CLI 工具
swift build -c release --product mdg
cp .build/release/mdg ~/.local/bin/mdg

# 预览文件
mdg README.md
mdg ~/Documents/notes.md
mdg ./docs/spec.md
```

**功能说明：**
- 支持绝对路径和相对路径
- 支持 `~` 表示主目录
- 自动查找已安装的 md-glance 应用

### QuickLook

在 Finder 中选中 Markdown 文件，按空格键即可快速预览。

## 🎯 功能边界

**包含：**
- 文件读取与内容渲染
- Markdown **源码编辑**与保存（与预览切换使用）
- GitHub Flavored Markdown
- LaTeX 数学公式（行内 `$` 与块级 `$$`）
- Mermaid 图表
- 代码语法高亮
- 实时文件监控与刷新（与未保存状态协调）
- TOC 目录导航
- QuickLook 扩展

**不包含：**
- 所见即所得（WYSIWYG）编辑
- 文件导出（PDF/HTML 等）
- 云同步
- 多标签页管理
- 自定义主题

## 📝 渲染流程

```
Markdown 原文
    ↓
preprocessMath()    # 多行 $$ 块转 HTML
    ↓
Ink MarkdownParser  # 解析标准 Markdown
    ├─ MermaidModifier  # ```mermaid → <div class="mermaid">
    ├─ MathModifier     # $/$$ → <span class="math-inline/display">
    └─ HeadingModifier  # <h*> → 注入 id，收集 TOC
    ↓
wrapInTemplate()    # 组装完整 HTML 页面
    ↓
WKWebView 渲染
```

## 🔧 开发

### 环境要求

- macOS 12.0 (Monterey) 或更高版本
- Xcode 14.0 或更高版本
- Swift 5.9+

### 运行测试

```bash
swift test
```

### 代码规范

项目遵循 [CLAUDE.md](CLAUDE.md) 中定义的开发规范。

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE)

## 📋 更新日志

### v1.2.0 (2026-04-03)

**新功能：**
- 主窗口 **预览 / 编辑** 双模式：等宽源码编辑、⌘S 与工具栏保存、未保存时在标题标注「已修改」
- 文件监控在编辑模式或有未保存修改时不覆盖缓冲区；切回预览且无未保存修改时会尝试与磁盘同步

**其他：**
- 打包脚本 `build-dmg.sh` 与 CLI/安装脚本等配套调整（详见提交记录）

### v1.1.1 (2026-03-01)

**Bug 修复：**
- 修复列表项中 HTML 标签被 Ink 误解析为块级元素的问题
  - 当列表项包含 ``` 描述和 HTML 标签时，Ink 会把 `<div>` 等标签当作原始 HTML 块级元素，导致后续内容被吸入未闭合的 div 中
  - 解决方案：在预处理阶段转义行内的 ``` 和 HTML 标签
- 修复行内 ``` 被解析为内联代码标记的问题
  - 转义为 HTML 实体确保按源码完整渲染

**性能优化：**
- 按需加载 KaTeX 和 Mermaid 库减少内存占用

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📮 联系方式

- GitHub: [@steptian](https://github.com/steptian)

---

<div align="center">

Made with ❤️ by [steptian](https://github.com/steptian)

</div>

---

## English

A minimalist and elegant native Markdown preview tool for macOS.

### Features

- 🎨 Beautiful GitHub-style rendering with dark mode support
- ✏️ **Preview & edit** - Switch between rendered preview and monospace source editing; **⌘S** saves to disk; window title shows when there are unsaved changes
- 🧮 LaTeX math formulas via KaTeX
- 📊 Mermaid diagrams (flowcharts, sequences, gantt charts)
- 💻 Syntax highlighting with highlight.js
- 📑 Auto-generated table of contents (preview mode)
- 🔄 Auto-refresh on external saves in preview; does not overwrite local edits while editing or when dirty
- 📜 Scroll position preservation
- 🖱️ Drag & drop to open
- 🔍 QuickLook extension

### Requirements

- macOS 12.0+ (Monterey)

### Building from Source

```bash
git clone https://github.com/steptian/md-glance.git
cd md-glance
swift build
swift run md-glance
```

### License

MIT
