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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
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
        window.contentView = NSHostingView(rootView: MainView().environmentObject(model))
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
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "移动硬盘测试", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0",
            .credits: NSAttributedString(string: "外接硬盘信息与 SMART 检测\n测速衔接 AmorphousDiskMark\n基于 smartmontools，非闪迪官方软件。")])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
