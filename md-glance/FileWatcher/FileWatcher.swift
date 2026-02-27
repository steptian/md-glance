//
//  FileWatcher.swift
//  md-glance
//
//  文件监控器 - 使用 DispatchSource + FSEvents 双重监控
//

import Foundation

/// 文件变更回调类型
public typealias FileChangeCallback = () -> Void

/// 文件监控器 - 监控指定文件的变更
///
/// 监控策略：
/// 1. 主监控：DispatchSourceFileSystemObject 监控文件描述符
/// 2. 兜底监控：FSEvents 监控文件系统事件（处理"删除后重建"等编辑器保存行为）
public class FileWatcher {

    // MARK: - Properties

    private let fileURL: URL
    private let onChange: FileChangeCallback

    /// DispatchSource 文件系统监控
    private var dispatchSource: DispatchSourceFileSystemObject?

    /// 文件描述符
    private var fileDescriptor: Int32 = -1

    /// FSEvents 监控流
    private var fsEventsStream: FSEventStreamRef?

    /// 上次修改时间（用于防抖）
    private var lastModificationTime: Date?

    /// 防抖延迟（毫秒）- 避免编辑器保存时触发多次刷新
    private let debounceDelay: TimeInterval = 0.1

    /// 防抖工作项
    private var debounceWorkItem: DispatchWorkItem?

    /// 调度队列
    private let queue = DispatchQueue(label: "com.mdglance.filewatcher", qos: .utility)

    // MARK: - Initialization

    public init(url: URL, onChange: @escaping FileChangeCallback) {
        self.fileURL = url
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// 启动文件监控
    public func start() {
        queue.async { [weak self] in
            self?.startDispatchSource()
            self?.startFSEvents()
        }
    }

    /// 停止文件监控
    public func stop() {
        queue.async { [weak self] in
            self?.stopDispatchSource()
            self?.stopFSEvents()
            self?.debounceWorkItem?.cancel()
        }
    }

    // MARK: - DispatchSource Monitoring

    /// 启动 DispatchSource 监控
    private func startDispatchSource() {
        // 打开文件描述符
        fileDescriptor = open(fileURL.path, O_EVTONLY)

        guard fileDescriptor != -1 else {
            NSLog("[FileWatcher] 无法打开文件描述符: \(fileURL.path)")
            return
        }

        // 创建 DispatchSource 监控文件系统事件
        // 监控：写入、删除、属性变更、重命名
        let eventMask: DispatchSource.FileSystemEvent = [
            .write,
            .delete,
            .attrib,
            .rename
        ]

        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: eventMask,
            queue: queue
        )

        // 设置事件处理器
        dispatchSource?.setEventHandler { [weak self] in
            self?.handleDispatchEvent()
        }

        // 设置取消处理器
        dispatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        // 启动监控
        dispatchSource?.resume()
        NSLog("[FileWatcher] DispatchSource 监控已启动: \(fileURL.lastPathComponent)")
    }

    /// 停止 DispatchSource 监控
    private func stopDispatchSource() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    /// 处理 DispatchSource 事件
    private func handleDispatchEvent() {
        let event = dispatchSource?.data ?? []

        // 检查文件是否被删除
        if event.contains(.delete) {
            NSLog("[FileWatcher] 文件被删除，尝试重新监控")
            // 取消当前监控
            stopDispatchSource()
            // 等待文件可能被重建
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restartIfNeeded()
            }
            return
        }

        // 检查文件是否被重命名
        if event.contains(.rename) {
            NSLog("[FileWatcher] 文件被重命名")
            stopDispatchSource()
            return
        }

        // 文件内容或属性变更
        if event.contains(.write) || event.contains(.attrib) {
            triggerChange()
        }
    }

    // MARK: - FSEvents Monitoring

    /// 启动 FSEvents 监控（兜底机制）
    private func startFSEvents() {
        let pathToWatch = fileURL.deletingLastPathComponent().path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // 创建 FSEvents 流
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallbackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let callbackInfo = clientCallbackInfo else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(callbackInfo).takeUnretainedValue()
                watcher.handleFSEvents(
                    numEvents: numEvents,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags
                )
            },
            &context,
            [pathToWatch] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // 延迟 0.5 秒，合并多个事件
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream = stream else {
            NSLog("[FileWatcher] FSEventStreamCreate 失败")
            return
        }

        fsEventsStream = stream

        // 在当前 runloop 中调度
        FSEventStreamSetDispatchQueue(stream, queue)

        // 启动流
        FSEventStreamStart(stream)
        NSLog("[FileWatcher] FSEvents 监控已启动: \(pathToWatch)")
    }

    /// 停止 FSEvents 监控
    private func stopFSEvents() {
        if let stream = fsEventsStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventsStream = nil
        }
    }

    /// 处理 FSEvents 事件
    private func handleFSEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        let paths = eventPaths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self)

        for i in 0..<numEvents {
            let path = String(cString: paths[i])
            let flags = FSEventStreamEventFlags(eventFlags[i])

            // 只处理我们关注的文件
            guard path == fileURL.path else { continue }

            // 检查是否是文件创建事件（处理"删除后重建"）
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
                NSLog("[FileWatcher] FSEvents: 文件被创建（重建）")
                restartIfNeeded()
                return
            }

            // 文件修改事件
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 ||
               flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
                triggerChange()
            }
        }
    }

    // MARK: - Helper Methods

    /// 触发变更回调（带防抖）
    private func triggerChange() {
        // 取消之前的防抖工作项
        debounceWorkItem?.cancel()

        // 创建新的防抖工作项
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // 检查文件是否确实存在
            guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
                NSLog("[FileWatcher] 文件不存在，跳过变更回调")
                return
            }

            // 检查修改时间是否真的变化了
            if let attributes = try? FileManager.default.attributesOfItem(atPath: self.fileURL.path),
               let newModTime = attributes[.modificationDate] as? Date {

                if let lastModTime = self.lastModificationTime,
                   newModTime <= lastModTime {
                    // 修改时间没有变化，跳过
                    return
                }

                self.lastModificationTime = newModTime
            }

            NSLog("[FileWatcher] 触发文件变更回调: \(self.fileURL.lastPathComponent)")

            // 在主线程执行回调
            DispatchQueue.main.async {
                self.onChange()
            }
        }

        debounceWorkItem = workItem

        // 延迟执行
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    /// 如果文件存在则重新启动监控
    private func restartIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("[FileWatcher] 文件不存在，等待恢复")
            return
        }

        NSLog("[FileWatcher] 重新启动监控: \(fileURL.lastPathComponent)")
        stopDispatchSource()
        startDispatchSource()
        triggerChange()
    }
}
