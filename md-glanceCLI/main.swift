//
//  main.swift
//  md-glanceCLI
//
//  CLI 命令行工具
//  使用 md-glance 打开 Markdown 文件预览
//

import Foundation
import AppKit

/// CLI 工具
/// 用法: md-glance <file.md>
@main
struct MDGlanceCLI {

    static func main() {
        // 获取命令行参数
        let arguments = CommandLine.arguments

        // 跳过第一个参数（可执行文件路径）
        let args = Array(arguments.dropFirst())

        // 解析参数
        switch args.count {
        case 0:
            // 没有参数，显示使用说明
            printUsage()
            exit(1)

        case 1:
            let filePath = args[0]
            openFile(filePath)

        default:
            print("错误: 参数过多")
            printUsage()
            exit(1)
        }
    }

    /// 查找项目根目录（通过 Package.swift 文件）
    private static func findProjectRoot() -> String? {
        // 从当前目录向上查找 Package.swift
        var currentPath = FileManager.default.currentDirectoryPath

        for _ in 0..<10 {
            let packagePath = currentPath + "/Package.swift"
            if FileManager.default.fileExists(atPath: packagePath) {
                return currentPath
            }

            // 向上一级
            let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
            if parent == currentPath {
                break
            }
            currentPath = parent
        }

        return nil
    }

    /// 打开 Markdown 文件
    /// - Parameter path: 文件路径
    private static func openFile(_ path: String) {
        // 处理路径扩展 (~)
        let expandedPath = NSString(string: path).expandingTildeInPath

        // 构建文件 URL
        let fileURL: URL
        if expandedPath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: expandedPath)
        } else {
            // 相对路径，基于当前工作目录
            fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expandedPath)
        }

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("错误: 文件不存在: \(fileURL.path)")
            exit(1)
        }

        // 检查是否是 Markdown 文件
        let validExtensions = ["md", "markdown", "mdown", "mkd", "mkdown"]
        let fileExtension = fileURL.pathExtension.lowercased()
        if !validExtensions.contains(fileExtension) {
            print("警告: 文件扩展名 '.\(fileExtension)' 不是标准的 Markdown 扩展名")
            print("支持的扩展名: \(validExtensions.joined(separator: ", "))")
            print("继续尝试打开...")
        }

        // 查找 md-glance 应用或可执行文件
        // 优先级：/Applications > ~/Applications > release > debug
        // 优先使用已安装版本，确保单实例行为一致
        let projectRoot = findProjectRoot()
        let appLocations: [String] = [
            "/Applications/md-glance.app",
            NSHomeDirectory() + "/Applications/md-glance.app",
            projectRoot.map { $0 + "/release/md-glance.app" },
            projectRoot.map { $0 + "/.build/debug/md-glance" }  // 开发调试时使用
        ].compactMap { $0 }

        var appPath: String?
        var isAppBundle = false
        for location in appLocations {
            let expanded = NSString(string: location).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                appPath = expanded
                isAppBundle = expanded.hasSuffix(".app")
                break
            }
        }

        // 如果找不到应用，尝试使用默认应用
        guard let foundPath = appPath else {
            // 使用系统默认应用打开
            let success = NSWorkspace.shared.open(fileURL)
            if success {
                print("正在打开: \(fileURL.lastPathComponent)")
            } else {
                print("错误: 无法打开文件")
                print("请确保 md-glance 应用已正确安装")
                exit(1)
            }
            return
        }

        // 根据类型选择启动方式
        if isAppBundle {
            // .app 包：通过 NSWorkspace 打开，走 Launch Services 流程
            // 这样可以正确激活窗口（Process 直接 spawn 会绕过 Launch Services，导致窗口不激活）
            openWithWorkspace(appPath: foundPath, fileURL: fileURL)
        } else {
            // 二进制文件：直接运行（开发调试场景，无 .app 包）
            openFileDirectly(appPath: foundPath, fileURL: fileURL)
        }
    }

    /// 通过 Launch Services 打开文件，确保应用正确激活到前台
    private static func openWithWorkspace(appPath: String, fileURL: URL) {
        let appURL = URL(fileURLWithPath: appPath)

        // 配置：显式激活应用到前台
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { app, error in
            if let error = error {
                print("错误: \(error.localizedDescription)")
                exit(1)
            }
            if app != nil {
                print("正在打开: \(fileURL.lastPathComponent)")
            }
        }

        // 保持进程运行足够长时间让应用启动
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
    }

    /// 直接运行应用并传递文件参数（仅用于开发调试时的二进制启动）
    private static func openFileDirectly(appPath: String, fileURL: URL) {
        let process = Process()
        let executablePath = appPath.hasSuffix(".app") ? appPath + "/Contents/MacOS/md-glance" : appPath
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [fileURL.path]
        do {
            try process.run()
            print("正在打开: \(fileURL.lastPathComponent)")
        } catch {
            print("错误: \(error.localizedDescription)")
            exit(1)
        }
    }

    /// 打印使用说明
    private static func printUsage() {
        print("""
        mdg - macOS Markdown 预览工具

        用法:
            mdg <file.md>

        参数:
            file.md    要预览的 Markdown 文件路径

        示例:
            mdg README.md
            mdg ~/Documents/notes.md
            mdg ./docs/spec.md

        说明:
            - 支持绝对路径和相对路径
            - 支持 ~ 表示主目录
            - 文件将在 md-glance 应用中打开
        """)
    }
}
