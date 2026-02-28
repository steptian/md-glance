# md-glance 待办事项

- 创建日期: 2026-02-28
- 最后更新: 2026-02-28

## ✅ 已解决问题

### 2026-02-28: 右键打开文件显示空白

- **解决方案**: 添加 `application(_:open:)` 方法和 `.onOpenURL` 修饰符
- **关键修改**:
  - `applicationShouldOpenUntitledFile` 返回 `true`
  - 使用 `GlobalFileState` 单例传递文件 URL
  - 移除自动关闭空窗口逻辑

### 2026-02-28: 命令行打开后窗口不激活

- **解决方案**: 添加 `NSApp.activate(ignoringOtherApps: true)`
- **关键代码**:
  ```swift
  NSApp.activate(ignoringOtherApps: true)
  if let window = NSApp.windows.first {
      window.makeKeyAndOrderFront(nil)
  }
  ```

### 2026-02-28: KaTeX 字体加载失败

- **现象**: `/fonts/KaTeX_*.woff2` 路径 404
- **原因**: CSS 中字体路径是相对路径，但 LocalResourceHandler 不支持
- **解决方案**: 在 LocalResourceHandler 中添加 `/fonts/` 路径支持

## 🟡 待优化

### 构建警告：未声明资源文件

- 已在 Package.swift 中配置排除，但仍需验证

### 文件被处理两次

- 命令行启动时，`openFiles` 和命令行参数都会处理文件
- 目前不影响功能，但可以优化
