import AppKit
import SwiftUI
import DiskCore

@main struct PortableDiskMain {
    static func main() {
        if CommandLine.arguments.contains("--scan-json") {
            do {
                let service = DiskService(smartctlPath: DiskService.locateSMART(executableDirectory: Bundle.main.executableURL?.deletingLastPathComponent()))
                let devices = try service.scan(force: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(devices))
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var window: NSWindow!
    var model: AppModel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        let args = CommandLine.arguments
        if let page = args.first(where: { $0.hasPrefix("--page=") })?.components(separatedBy: "=").last {
            model.page = page == "smart" ? .smart : page == "speed" ? .speed : .overview
        }
        let size: NSSize = args.contains("--compact") ? NSSize(width: 960, height: 720) : NSSize(width: 1180, height: 820)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "移动硬盘测试"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true; window.minSize = NSSize(width: 960, height: 720)
        if args.contains("--dark") { window.appearance = NSAppearance(named: .darkAqua) }
        if args.contains("--light") { window.appearance = NSAppearance(named: .aqua) }
        let hostingView = NSHostingView(rootView: MainView().environmentObject(model))
        // Keep status banners from resizing the user's window through intrinsic sizing.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        configureMenu()
        model.start()
        if let capture = args.first(where: { $0.hasPrefix("--capture=") })?.dropFirst("--capture=".count) {
            Task { @MainActor in
                for _ in 0..<100 {
                    if self.model.hasScanned { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if let deviceID = args.first(where: { $0.hasPrefix("--device=") })?.dropFirst("--device=".count) {
                    self.model.selectedID = String(deviceID)
                }
                if args.contains("--empty-preview") { self.model.devices = []; self.model.selectedID = nil }
                if let state = args.first(where: { $0.hasPrefix("--eject-preview=") })?.components(separatedBy: "=").last {
                    self.previewEjection(state)
                }
                if args.contains("--label-editor-preview"), let disk = self.model.selected {
                    self.model.labelEditor = LabelEditorTarget(disk: disk)
                }
                if let purpose = args.first(where: { $0.hasPrefix("--purpose=") })?.dropFirst("--purpose=".count) {
                    self.model.benchmarkPurpose = purpose == "quick" ? .quick : purpose == "large" ? .workingSet : .comparison
                }
                if let file = args.first(where: { $0.hasPrefix("--import-preview=") })?.dropFirst("--import-preview=".count),
                   let text = try? String(contentsOfFile: String(file), encoding: .utf8) {
                    self.model.importCandidate = try? BenchmarkParser.parse(text)
                }
                try? await Task.sleep(nanoseconds: args.contains("--label-editor-preview") ? 2_000_000_000 : 800_000_000)
                for _ in 0..<250 {
                    if !self.model.isRecognizingLabelPhoto { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                let view = self.window.attachedSheet?.contentView ?? self.window.contentView!
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(capture)))
                }
                // 捕获模式不进入活动 sheet 的交互式退出流程。
                exit(0)
            }
        }
    }
    func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于移动硬盘测试", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏移动硬盘测试", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出移动硬盘测试", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let diskItem = NSMenuItem(); let diskMenu = NSMenu(title: "磁盘")
        diskMenu.addItem(withTitle: "安全推出所选硬盘", action: #selector(ejectSelected), keyEquivalent: "e")
        let export = NSMenuItem(title: "导出报告…", action: #selector(exportSelected), keyEquivalent: "E")
        export.keyEquivalentModifierMask = [.command, .shift]
        diskMenu.addItem(export)
        diskItem.submenu = diskMenu; main.addItem(diskItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(); let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu; main.addItem(windowItem); NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }
    @objc func ejectSelected() { if let disk = model.selected, model.canEject { model.requestEject(disk) } }
    @objc func exportSelected() { if let disk = model.selected { model.export(disk) } }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(ejectSelected) { return model.canEject && window.attachedSheet == nil }
        if menuItem.action == #selector(exportSelected) { return model.selected != nil && model.ejectingDisk == nil && window.attachedSheet == nil }
        return true
    }
    private func previewEjection(_ state: String) {
        // Called only inside --capture=. Never invokes a real unmount or eject.
        var snapshot = SMARTSnapshot(); snapshot.model = "SanDisk Extreme Pro USB4（示例）"
        snapshot.serial = "SYNTHETIC-EJECT"; snapshot.health = .passed
        snapshot.explanation = "这是用于验证安全推出界面的合成设备，未执行真实硬盘操作。"
        var disk = DiskDevice(id: "disk999", mediaName: "Extreme Pro（示例）", capacity: 4e12, bus: "USB", solidState: true,
            partitionMap: "GUID_partition_scheme", volumes: [DiskVolume(id: "disk999s1", uuid: "SYNTHETIC-VOLUME", name: "Extreme Pro（示例）",
                mountPoint: "/Volumes/SYNTHETIC-EJECT", filesystem: "ExFAT", capacity: 4e12, free: 3.9e12, writable: true)], snapshot: snapshot)
        disk.mediaRegistryID = UInt64.max
        model.devices = [disk]; model.selectedID = disk.id; model.discoveryError = nil
        switch state {
        case "pending": model.ejectingDisk = disk
        case "busy": model.ejectionFeedback = EjectionFeedback(title: "“\(disk.displayName)”未能安全推出", message: DiskEjectError.busy.localizedDescription + " 请先不要拔线。", failed: true)
        case "success":
            model.devices = []; model.selectedID = nil
            model.ejectionFeedback = EjectionFeedback(title: "已安全推出“\(disk.displayName)”", message: "现在可以拔下这块硬盘的连接线。", failed: false,
                receipt: DiskEjectionReceipt(targetRegistryID: UInt64.max, otherConnectedRegistryIDs: []))
        case "reconnected":
            model.ejectionFeedback = EjectionFeedback(title: "已安全推出“\(disk.displayName)”", message: "现在可以拔下这块硬盘的连接线。", failed: false,
                receipt: DiskEjectionReceipt(targetRegistryID: UInt64.max - 1, otherConnectedRegistryIDs: []))
            model.reconcileEjectionFeedback(with: Set(model.devices.compactMap(\.mediaRegistryID)))
        case "multiple":
            var second = disk.volumes[0]; second.id = "disk999s2"; second.uuid = "SYNTHETIC-VOLUME-2"; second.name = "备份卷（示例）"
            disk.volumes.append(second); model.devices = [disk]; model.ejectConfirmation = disk
        case "stale": model.discoveryError = "示例：设备发现暂时失败，请重新扫描。"
        default: break
        }
    }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "移动硬盘测试", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.0",
            .credits: NSAttributedString(string: "外接硬盘信息与 SMART 检测\n测速衔接 AmorphousDiskMark\n基于 smartmontools，非闪迪官方软件。")])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
