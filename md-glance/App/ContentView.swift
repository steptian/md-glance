//
//  ContentView.swift
//  md-glance
//
//  主界面视图
//

import SwiftUI
import AppKit
import WebKit
import md_glanceCore
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var documentManager: DocumentManager
    @State private var currentWindow: NSWindow?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var saveFailed = false

    /// 保留用于拖放新文件时创建新窗口
    @State private var lastOpenedPath: String?

    init(documentManager: DocumentManager) {
        self.documentManager = documentManager
    }

    /// 便利初始化方法，用于创建新窗口（如标签页）
    init(fileURL: URL? = nil) {
        self.documentManager = DocumentManager(fileURL: fileURL)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 顶部进度条（仅预览模式）
                if documentManager.fileURL != nil, documentManager.viewMode == .preview {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 背景轨道
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                            // 进度条
                            Rectangle()
                                .fill(Color.gray.opacity(0.6))
                                .frame(width: geometry.size.width * documentManager.scrollProgress)
                        }
                    }
                    .frame(height: 2)
                }

                // 主内容
                Group {
                    if documentManager.fileURL != nil {
                        Group {
                            if documentManager.viewMode == .preview {
                                HStack(spacing: 0) {
                                    MarkdownWebViewWrapper(
                                        documentManager: documentManager,
                                        onFileDrop: { url in
                                            handleFileDrop(url)
                                        }
                                    )
                                    .id(documentManager.fileURL)
                                    .frame(maxWidth: .infinity)

                                    if !documentManager.tocItems.isEmpty {
                                        TOCSidebarView(
                                            items: documentManager.tocItems,
                                            currentSlug: documentManager.currentHeadingSlug,
                                            onSelect: { slug in
                                                documentManager.scrollToHeading(slug: slug)
                                            }
                                        )
                                        .frame(width: documentManager.showTOC ? 220 : 0)
                                        .clipped()
                                    }
                                }
                            } else {
                                MarkdownSourceEditor(text: $documentManager.content)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(8)
                            }
                        }
                    } else {
                        EmptyStateView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }

            // Toast 提示
            if showToast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(toastMessage)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(navigationTitleText)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .toolbar {
            ToolbarItemGroup {
                if documentManager.fileURL != nil {
                    Picker("", selection: $documentManager.viewMode) {
                        ForEach(MarkdownViewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 140)
                    .onChange(of: documentManager.viewMode) { newMode in
                        if newMode == .preview {
                            documentManager.syncFromDiskIfCleanPreservingScroll()
                        }
                    }

                    Divider()
                        .frame(height: 12)

                    Button(action: saveDocument) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(documentManager.isDirty ? .accentColor : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("保存到磁盘 (⌘S)")
                    .keyboardShortcut("s", modifiers: .command)

                    Divider()
                        .frame(height: 12)

                    // 统计信息
                    Text("\(documentManager.wordCount) 字  \(documentManager.lineCount) 行")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Divider()
                        .frame(height: 12)

                    // 复制全文按钮
                    Button(action: {
                        copyAllText()
                        toastMessage = "已复制到剪贴板"
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showToast = false
                            }
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("复制全文")

                    if documentManager.viewMode == .preview {
                        Divider()
                            .frame(height: 12)

                        // 目录按钮
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                documentManager.showTOC.toggle()
                            }
                        }) {
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(documentManager.showTOC ? .accentColor : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(documentManager.showTOC ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(documentManager.showTOC ? "隐藏目录" : "显示目录")
                    }
                }
            }
        }
        .alert("无法保存文件", isPresented: $saveFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请检查磁盘权限或文件是否被其他应用占用。")
        }
        .onAppear {
            // 保存窗口引用
            DispatchQueue.main.async {
                self.currentWindow = NSApplication.shared.keyWindow
            }

            // 检查全局状态中是否有文件要打开
            if let url = GlobalFileState.shared.currentFileURL {
                let path = url.standardizedFileURL.path
                if lastOpenedPath != path {
                    NSLog("[ContentView] 📂 启动时打开文件: \(url.lastPathComponent)")
                    lastOpenedPath = path
                    documentManager.openFile(url)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mdGlanceSaveDocument)) { _ in
            saveDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FileOpened"))) { notification in
            if let url = notification.object as? URL {
                let path = url.standardizedFileURL.path
                if lastOpenedPath != path {
                    NSLog("[ContentView] 📂 监听收到文件打开通知: \(url.lastPathComponent)")
                    lastOpenedPath = path
                    documentManager.openFile(url)
                }
            }
        }
    }

    private var navigationTitleText: String {
        let base = documentManager.fileURL?.lastPathComponent ?? "md-glance"
        guard documentManager.fileURL != nil else { return base }
        return documentManager.isDirty ? "\(base) （已修改）" : base
    }

    private func saveDocument() {
        guard documentManager.fileURL != nil else { return }
        if documentManager.saveToDisk() {
            toastMessage = "已保存"
            withAnimation(.easeInOut(duration: 0.2)) {
                showToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showToast = false
                }
            }
        } else {
            saveFailed = true
        }
    }

    private func updateWindowTitle() {
        if let url = documentManager.fileURL {
            NSApplication.shared.windows.first { $0.isKeyWindow }?.title = url.lastPathComponent
        }
    }

    private func copyAllText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(documentManager.content, forType: .string)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension == "md" else { return }
            DispatchQueue.main.async {
                self.handleFileDrop(url)
            }
        }
        return true
    }

    private func handleFileDrop(_ url: URL) {
        // 如果当前窗口没有文件，直接打开
        if documentManager.fileURL == nil {
            documentManager.openFile(url)
            updateWindowTitle()
            return
        }

        // 如果拖入的是同一个文件，忽略
        if documentManager.fileURL == url {
            return
        }

        // 在新标签页中打开
        openFileInNewTab(url)
    }

    private func openFileInNewTab(_ url: URL) {
        // 获取当前窗口（优先使用保存的引用）
        let targetWindow = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first

        guard let currentWindow = targetWindow else {
            openFileInNewWindow(url)
            return
        }

        // 创建新窗口
        let newContentView = ContentView(fileURL: url)
        let newWindow = NSWindow(
            contentRect: currentWindow.frame,
            styleMask: currentWindow.styleMask,
            backing: .buffered,
            defer: false
        )
        newWindow.contentView = NSHostingView(rootView: newContentView)
        newWindow.title = url.lastPathComponent

        // 添加为标签页
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    private func openFileInNewWindow(_ url: URL) {
        // 使用 macOS 原生方式打开新窗口/标签
        if let window = NSApplication.shared.windows.first {
            let newContentView = ContentView(fileURL: url)
            let newWindow = NSWindow(
                contentRect: window.frame,
                styleMask: window.styleMask,
                backing: .buffered,
                defer: false
            )
            newWindow.contentView = NSHostingView(rootView: newContentView)
            newWindow.title = url.lastPathComponent
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
}

/// 目录侧边栏视图
struct TOCSidebarView: View {
    let items: [TOCItem]
    let currentSlug: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 目录列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(items) { item in
                        TOCItemView(
                            item: item,
                            isActive: item.slug == currentSlug,
                            onSelect: { onSelect(item.slug) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
        .frame(minWidth: 180, maxWidth: 250)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 单个目录项视图
struct TOCItemView: View {
    let item: TOCItem
    let isActive: Bool
    let onSelect: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                ForEach(0..<max(0, item.level - 1), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 16)
                }

                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 3)

                Text(item.title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isActive ? .accentColor : .primary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.12) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// WebView 包装器
struct MarkdownWebViewWrapper: View {
    @ObservedObject var documentManager: DocumentManager
    var onFileDrop: ((URL) -> Void)?

    var body: some View {
        MarkdownWebView(
            markdown: documentManager.content,
            baseURL: documentManager.fileURL?.deletingLastPathComponent(),
            onWebViewCreated: { createdWebView in
                documentManager.setWebView(createdWebView)
            },
            onRenderComplete: {
                // 标记渲染完成，触发淡入动画
                documentManager.markRendered()
                if documentManager.scrollPosition > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        restoreScrollPosition()
                    }
                }
            },
            onScroll: {
                documentManager.saveScrollPosition()
                documentManager.updateCurrentHeading()
                documentManager.updateScrollProgress()
            },
            onRendererReady: { renderer in
                documentManager.setRenderer(renderer)
            },
            onFileDrop: onFileDrop
        )
        .opacity(documentManager.isRendered ? 1 : 0)
        .animation(.easeIn(duration: 0.25), value: documentManager.isRendered)
    }

    private func restoreScrollPosition() {
        guard let webView = documentManager.webView else { return }
        let position = documentManager.scrollPosition
        webView.evaluateJavaScript("window.scrollTo(0, \(position))")
    }
}

/// 空状态视图
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("打开 Markdown 文件开始")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("⌘O 打开，或拖入 .md；打开后可用工具栏在预览与编辑间切换")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 源码编辑（等宽 NSTextView）
struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = text
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = false
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textView = textView
        if textView.string != text {
            let range = textView.selectedRange()
            textView.string = text
            let len = (text as NSString).length
            if range.location <= len {
                let loc = min(range.location, len)
                let rem = max(0, len - loc)
                let newLen = min(range.length, rem)
                textView.setSelectedRange(NSRange(location: loc, length: newLen))
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor
        weak var textView: NSTextView?

        init(_ parent: MarkdownSourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }
    }
}
