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

        // 使用 NSWorkspace 打开文件
        // 这会使用注册的默认应用（md-glance）打开 .md 文件
        let success = NSWorkspace.shared.open(fileURL)

        if success {
            print("正在打开: \(fileURL.lastPathComponent)")
        } else {
            print("错误: 无法打开文件")
            print("请确保 md-glance 应用已正确安装")
            exit(1)
        }
    }

    /// 打印使用说明
    private static func printUsage() {
        print("""
        md-glance - macOS Markdown 预览工具

        用法:
            md-glance <file.md>

        参数:
            file.md    要预览的 Markdown 文件路径

        示例:
            md-glance README.md
            md-glance ~/Documents/notes.md
            md-glance ./docs/spec.md

        说明:
            - 支持绝对路径和相对路径
            - 支持 ~ 表示主目录
            - 文件将在 md-glance 应用中打开
        """)
    }
}
