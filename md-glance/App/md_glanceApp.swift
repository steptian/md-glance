//
//  md_glanceApp.swift
//  md-glance
//
//  macOS Markdown 预览工具
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - AppDelegate 处理单实例文件打开

class AppDelegate: NSObject, NSApplicationDelegate {

    /// 处理单实例模式下通过命令行打开文件
    /// 当应用已在运行时，系统会调用此方法
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        print("[AppDelegate] 📂 application(_:openFile:) 被调用: \(filename)")
        let fileURL = URL(fileURLWithPath: filename)
        openFileURL(fileURL)
        return true
    }

    /// 处理多个文件打开（Apple Event 方式）
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        print("[AppDelegate] 📂 application(_:openFiles:) 被调用: \(filenames)")
        for filename in filenames {
            let fileURL = URL(fileURLWithPath: filename)
            openFileURL(fileURL)
        }
    }

    private func openFileURL(_ fileURL: URL) {
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[AppDelegate] ❌ 文件不存在: \(fileURL.path)")
            return
        }

        // 激活应用
        NSApp.activate(ignoringOtherApps: true)

        // 在主线程打开文件
        DispatchQueue.main.async {
            print("[AppDelegate] ✅ 正在打开文件: \(fileURL.lastPathComponent)")
            self.openFileInNewWindow(fileURL)
        }
    }

    private func openFileInNewWindow(_ url: URL) {
        let newContentView = ContentView(fileURL: url)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.contentView = NSHostingView(rootView: newContentView)
        newWindow.title = url.lastPathComponent
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        print("[AppDelegate] 🪟 新窗口已创建: \(url.lastPathComponent)")
    }
}

@main
struct md_glanceApp: App {
    /// 注册 AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// 从命令行参数解析的初始文件 URL
    @State private var initialFileURL: URL?

    init() {
        // 解析命令行参数，支持启动时指定文件
        // 用法: md-glance /path/to/file.md
        let filePath = Self.parseCommandLineFilePath()
        _initialFileURL = State(initialValue: filePath.map { URL(fileURLWithPath: $0) })

        // 确保应用窗口激活（当从命令行启动时）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            // 强制显示窗口
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(fileURL: initialFileURL)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    // 确保窗口在出现时激活
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("md-glance 帮助") {
                    openHelp()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .windowArrangement) {
                Button("关闭标签页") {
                    closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
    }

    private func closeCurrentTab() {
        if let window = NSApplication.shared.keyWindow {
            // 如果窗口有多个标签，关闭当前标签
            if window.tabbedWindows?.count ?? 0 > 1 {
                window.close()
            } else {
                // 只有一个标签时，关闭窗口
                window.close()
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .item]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                openFileInNewWindow(url)
            }
        }
    }

    private func openHelp() {
        var helpURL: URL?
        // 1) SPM 资源 bundle：Contents/Resources/md-glance_md-glance.bundle/HELP.md
        let resourcesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
        let appBundleURL = resourcesURL.appendingPathComponent("md-glance_md-glance.bundle", isDirectory: true)
        let helpInBundle = appBundleURL.appendingPathComponent("HELP.md", isDirectory: false)
        if FileManager.default.fileExists(atPath: helpInBundle.path) {
            helpURL = helpInBundle
        }
        // 2) 主 bundle 根资源
        if helpURL == nil {
            helpURL = Bundle.main.url(forResource: "HELP", withExtension: "md")
        }
        // 3) 主 bundle 的 Contents/Resources 直放
        if helpURL == nil {
            let direct = resourcesURL.appendingPathComponent("HELP.md", isDirectory: false)
            if FileManager.default.fileExists(atPath: direct.path) { helpURL = direct }
        }
        if let url = helpURL {
            openFileInNewWindow(url)
        }
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

    // MARK: - 命令行参数解析

    /// 解析命令行参数中的文件路径
    /// - Returns: 文件路径字符串，如果没有有效参数则返回 nil
    private static func parseCommandLineFilePath() -> String? {
        let arguments = CommandLine.arguments

        // arguments[0] 是应用本身路径，从 index 1 开始检查
        guard arguments.count > 1 else { return nil }

        // 遍历参数，查找有效的文件路径
        for i in 1..<arguments.count {
            let arg = arguments[i]

            // 跳过 macOS 系统参数（如 -NSDocumentRevisionsDebugMode）
            if arg.hasPrefix("-") { continue }

            // 支持相对路径和绝对路径
            let filePath = (arg as NSString).expandingTildeInPath

            // 检查文件是否存在
            if FileManager.default.fileExists(atPath: filePath) {
                return filePath
            }

            // 尝试作为相对路径解析
            let currentDir = FileManager.default.currentDirectoryPath
            let absolutePath = (currentDir as NSString).appendingPathComponent(arg)
            if FileManager.default.fileExists(atPath: absolutePath) {
                return absolutePath
            }
        }

        return nil
    }
}
