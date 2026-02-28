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

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSLog("[AppDelegate] applicationShouldOpenUntitledFile: true (允许创建窗口以接收文件打开事件)")
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSLog("[AppDelegate] applicationShouldHandleReopen: hasVisibleWindows=\(flag)")
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

        // 更新全局状态
        DispatchQueue.main.async {
            GlobalFileState.shared.currentFileURL = fileURL
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] 🚀 应用启动完成")

        // 先检查命令行参数
        if CommandLine.arguments.count > 1 {
            for i in 1..<CommandLine.arguments.count {
                let arg = CommandLine.arguments[i]
                if !arg.hasPrefix("-") {
                    let path = (arg as NSString).expandingTildeInPath
                    if FileManager.default.fileExists(atPath: path) {
                        NSLog("[AppDelegate] 📂 命令行参数文件: \(path)")
                        handleFileOpen(path)
                        break
                    }
                }
            }
        }

        // 不再自动关闭窗口 - 窗口需要保持打开以接收文件打开事件
        // 如果用户启动应用时没有文件，会显示空状态视图
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
