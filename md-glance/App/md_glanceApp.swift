//
//  md_glanceApp.swift
//  md-glance
//
//  macOS Markdown 预览工具
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct md_glanceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
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
}
