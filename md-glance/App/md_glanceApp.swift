//
//  md_glanceApp.swift
//  md-glance
//
//  macOS Markdown 预览工具
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// 全局文件状态 - 用于跨视图共享文件 URL
class GlobalFileState: ObservableObject {
    static let shared = GlobalFileState()
    @Published var currentFileURL: URL?
    private init() {}
}

// AppDelegate - 处理文件打开
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasOpenedFile = false
    private var activationRetryCount = 0
    private let maxActivationRetries = 10

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSLog("[AppDelegate] applicationShouldOpenUntitledFile: true (允许创建窗口以接收文件打开事件)")
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSLog("[AppDelegate] applicationShouldHandleReopen: hasVisibleWindows=\(flag)")
        // 如果没有可见窗口且有文件待打开，强制激活
        if !flag && GlobalFileState.shared.currentFileURL != nil {
            NSLog("[AppDelegate] 🔄 检测到有文件待打开但无可见窗口，强制激活")
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    // 处理单个文件打开
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        NSLog("[AppDelegate] 📂 openFile: \(filename)")
        handleFileOpen(filename)
        return true
    }

    // 处理多个文件打开
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        NSLog("[AppDelegate] 📂 openFiles: \(filenames)")
        for filename in filenames {
            handleFileOpen(filename)
        }
    }

    // 处理 URL 打开（macOS 10.13+）
    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("[AppDelegate] 📂 open URLs: \(urls.map { $0.lastPathComponent })")
        for url in urls {
            handleFileURL(url)
        }
    }

    private func handleFileOpen(_ filename: String) {
        let fileURL = URL(fileURLWithPath: filename)
        handleFileURL(fileURL)
    }

    private func handleFileURL(_ fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("[AppDelegate] ❌ 文件不存在: \(fileURL.path)")
            return
        }

        guard fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" else {
            NSLog("[AppDelegate] ⚠️ 非 Markdown 文件: \(fileURL.pathExtension)")
            return
        }

        NSLog("[AppDelegate] ✅ 处理文件打开: \(fileURL.lastPathComponent)")
        hasOpenedFile = true

        // 立即激活应用，促使 SwiftUI 尽快创建窗口
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 更新全局状态
        DispatchQueue.main.async {
            GlobalFileState.shared.currentFileURL = fileURL
        }

        // 延迟激活窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.activateAndBringToFront()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] 🚀 应用启动完成")

        // 确保应用可以激活到前台
        NSApp.setActivationPolicy(.regular)

        // 立即激活一次
        NSApp.activate(ignoringOtherApps: true)

        // 启动重试机制，等待 SwiftUI 创建窗口
        retryActivation()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSLog("[AppDelegate] 🔔 应用已激活")
        // 确保窗口在最前面
        DispatchQueue.main.async {
            self.activateAndBringToFront()
        }
    }

    private func retryActivation() {
        activationRetryCount += 1
        NSLog("[AppDelegate] 🔄 重试激活 (\(activationRetryCount)/\(maxActivationRetries))，窗口数: \(NSApp.windows.count)")

        NSApp.activate(ignoringOtherApps: true)

        if NSApp.windows.isEmpty && activationRetryCount < maxActivationRetries {
            // 窗口还未创建，继续重试
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.retryActivation()
            }
        } else {
            // 窗口已创建或达到最大重试次数，执行最终激活
            activateAndBringToFront()
        }
    }

    private func activateAndBringToFront() {
        NSApp.activate(ignoringOtherApps: true)

        // 遍历所有窗口并激活
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        NSLog("[AppDelegate] ✅ 窗口已激活，窗口数: \(NSApp.windows.count)")
    }
}

@main
struct md_glanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            SharedContentView()
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    NSLog("[WindowGroup] Window appeared")
                    // 窗口出现时立即激活
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                        }
                    }
                }
                // 处理应用已运行时的文件打开
                .onOpenURL { url in
                    NSLog("[onOpenURL] 📂 收到文件: \(url.lastPathComponent)")
                    handleFileURL(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("保存") {
                    NotificationCenter.default.post(name: .mdGlanceSaveDocument, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func handleFileURL(_ url: URL) {
        guard url.pathExtension == "md" || url.pathExtension == "markdown" else {
            NSLog("[handleFileURL] ⚠️ 非 Markdown 文件: \(url.pathExtension)")
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[handleFileURL] ❌ 文件不存在: \(url.path)")
            return
        }

        NSLog("[handleFileURL] ✅ 正在打开文件: \(url.lastPathComponent)")

        // 激活应用并置顶窗口
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        GlobalFileState.shared.currentFileURL = url
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .item]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            if let url = panel.urls.first {
                GlobalFileState.shared.currentFileURL = url
            }
        }
    }
}

// 共享内容视图 - 监听全局文件状态
struct SharedContentView: View {
    @ObservedObject private var globalState = GlobalFileState.shared
    @StateObject private var documentManager: DocumentManager
    @State private var lastOpenedPath: String?

    init() {
        _documentManager = StateObject(wrappedValue: DocumentManager(fileURL: nil))
    }

    var body: some View {
        ContentView(documentManager: documentManager)
            .onAppear {
                NSLog("[SharedContentView] 🎬 onAppear 触发, currentFileURL=\(globalState.currentFileURL?.path ?? "nil")")

                // 激活窗口到最前面 - 使用更可靠的方法
                DispatchQueue.main.async {
                    // 1. 确保应用策略正确
                    NSApp.setActivationPolicy(.regular)
                    // 2. 激活应用
                    NSApp.activate(ignoringOtherApps: true)
                    // 3. 找到当前视图所在的窗口并激活
                    if let window = NSApp.windows.last {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                        // 4. 再次确保应用在最前面
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    NSLog("[SharedContentView] ✅ 窗口已激活，窗口数: \(NSApp.windows.count)")
                }

                // 处理初始文件（如果在视图创建前就设置了）
                if let url = globalState.currentFileURL {
                    let path = url.standardizedFileURL.path
                    NSLog("[SharedContentView] 📂 onAppear 检查: lastOpenedPath=\(lastOpenedPath ?? "nil"), path=\(path)")
                    if lastOpenedPath != path {
                        NSLog("[SharedContentView] 📂 初始文件: \(url.lastPathComponent)")
                        lastOpenedPath = path
                        documentManager.openFile(url)
                    }
                }
            }
            .onChange(of: globalState.currentFileURL) { newURL in
                NSLog("[SharedContentView] 📥 onChange 触发: \(newURL?.path ?? "nil")")
                if let url = newURL {
                    let path = url.standardizedFileURL.path
                    NSLog("[SharedContentView] 📂 onChange 检查: lastOpenedPath=\(lastOpenedPath ?? "nil"), path=\(path)")
                    if lastOpenedPath != path {
                        NSLog("[SharedContentView] 📂 正在打开文件: \(url.lastPathComponent)")
                        lastOpenedPath = path
                        documentManager.openFile(url)
                    } else {
                        NSLog("[SharedContentView] ⚠️ 跳过重复文件: \(path)")
                    }
                }
            }
    }
}
