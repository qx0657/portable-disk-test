import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DiskCore

enum DetailPage: String, CaseIterable, Identifiable {
    case overview = "概览", smart = "SMART", speed = "测速"
    var id: String { rawValue }
}

struct LabelEditorTarget: Identifiable {
    let id = UUID()
    let disk: DiskDevice
    let identity: String?
    init(disk: DiskDevice) { self.disk = disk; identity = disk.labelIdentity }
}

struct EjectionFeedback {
    let title: String
    let message: String
    let failed: Bool
    var receipt: DiskEjectionReceipt? = nil
}

@MainActor final class AppModel: ObservableObject {
    @Published var devices: [DiskDevice] = []
    @Published var selectedID: String?
    @Published var page: DetailPage = .overview
    @Published var benchmarkPurpose: BenchmarkPurpose = .comparison
    @Published var isRefreshing = false
    @Published var hasScanned = false
    @Published var discoveryError: String?
    @Published var notice: String?
    @Published var ejectingDisk: DiskDevice?
    @Published var ejectConfirmation: DiskDevice?
    @Published var ejectionFeedback: EjectionFeedback?
    @Published var ejectionIsSlow = false
    @Published var importCandidate: BenchmarkResult?
    @Published var records: [String: DeviceRecord] = [:]
    @Published var historyError: String?
    @Published var labels: [String: DeviceLabel] = [:]
    @Published var labelError: String?
    @Published var labelEditor: LabelEditorTarget?
    @Published var isRecognizingLabelPhoto = false
    @Published var automatic = UserDefaults.standard.object(forKey: "automatic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "automatic") }
    }
    let service: DiskService
    private var scanning = false
    private var ejectedMediaIDs = Set<UInt64>()
    private var monitor: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private let historyURL: URL
    private var historyReadable = true
    private var labelsReadable = true
    private let labelStore: DeviceLabelStore
    var selected: DiskDevice? { devices.first { $0.id == selectedID } }
    var benchmarkAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.katsurashareware.AmorphousDiskMark") ??
        ["/Applications/AmorphousDiskMark.app", NSHomeDirectory() + "/Applications/AmorphousDiskMark.app"]
            .first(where: { FileManager.default.fileExists(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    init() {
        service = DiskService(smartctlPath: DiskService.locateSMART(executableDirectory: Bundle.main.executableURL?.deletingLastPathComponent()))
        historyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortableDiskTest/history.json")
        labelStore = DeviceLabelStore(url: historyURL.deletingLastPathComponent().appendingPathComponent("device-labels.json"))
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do { records = try JSONDecoder().decode([String: DeviceRecord].self, from: Data(contentsOf: historyURL)) }
            catch { historyReadable = false; historyError = "历史记录文件未能读取，原文件已保留；当前数据仍可查看。" }
        }
        do { labels = try labelStore.load() }
        catch { labelsReadable = false; labelError = DeviceLabelError.unreadable.localizedDescription }
    }
    func start() {
        guard monitor == nil else { return }
        for event in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { [weak self] notification in
                let mounted = notification.name == NSWorkspace.didMountNotification
                Task { @MainActor in
                    if mounted {
                        self?.reconcileEjectionFeedback(with: nil)
                        // A user or another tool may mount the same IOMedia without a physical replug.
                        self?.ejectedMediaIDs.removeAll()
                    }
                    await self?.refresh(force: true, showProgress: false)
                }
            })
        }
        monitor = Task { [weak self] in
            await self?.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                if self?.automatic == true { await self?.refresh(force: false, showProgress: false) }
            }
        }
    }
    func refresh(force: Bool, showProgress: Bool = true) async {
        guard !scanning, ejectingDisk == nil else { return }
        scanning = true
        if showProgress { isRefreshing = true }
        defer { scanning = false; isRefreshing = false; hasScanned = true }
        let cached = devices, service = service, excluded = ejectedMediaIDs
        do {
            let result = try await Task.detached(priority: .utility) { try service.scan(cached: cached, force: force, excluding: excluded) }.value
            reconcileEjectionFeedback(with: Set(result.compactMap(\.mediaRegistryID)))
            devices = result; discoveryError = nil
            if !result.contains(where: { $0.id == selectedID }) { selectedID = result.first?.id }
            var changed = false
            for disk in result {
                guard let identity = disk.persistentIdentity else { continue }
                var record = records[identity] ?? DeviceRecord()
                if let temp = disk.snapshot.temperature, record.samples.last?.date != disk.snapshot.date {
                    record.samples.append(TemperatureSample(date: disk.snapshot.date, celsius: temp))
                    record.samples = Array(record.samples.suffix(180)); changed = true
                }
                if records[identity] == nil { changed = true }
                records[identity] = record
            }
            if changed { saveHistory() }
        } catch {
            // 发现失败时保留上次数据，并明确标记为旧数据；不把空结果当成设备全拔出。
            discoveryError = error.localizedDescription
            reconcileEjectionFeedback(with: nil)
        }
    }
    func reconcileEjectionFeedback(with registryIDs: Set<UInt64>?) {
        guard var feedback = ejectionFeedback, var receipt = feedback.receipt else { return }
        receipt.reconcile(connectedRegistryIDs: registryIDs)
        if !receipt.isValid { ejectionFeedback = nil }
        else { feedback.receipt = receipt; ejectionFeedback = feedback }
    }
    var canEject: Bool {
        selected?.mediaRegistryID != nil && ejectingDisk == nil && discoveryError == nil && !isRefreshing
    }
    func requestEject(_ disk: DiskDevice) {
        guard ejectingDisk == nil, discoveryError == nil else { return }
        if disk.volumes.filter({ $0.mountPoint != nil }).count > 1 { ejectConfirmation = disk }
        else { Task { await eject(disk) } }
    }
    func eject(_ target: DiskDevice) async {
        // Diagnostic previews must never unmount real user volumes.
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--capture=") }), ejectingDisk == nil else { return }
        ejectingDisk = target; ejectionFeedback = nil; ejectionIsSlow = false
        let slowNotice = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if !Task.isCancelled { ejectionIsSlow = true }
        }
        do {
            // Let in-flight SMART readers close before requesting the system unmount.
            while scanning { try await Task.sleep(nanoseconds: 100_000_000) }
            guard discoveryError == nil, let id = target.mediaRegistryID,
                  devices.contains(where: { $0.id == target.id && $0.mediaRegistryID == id }) else { throw DiskEjectError.changed }
            try await DiskEjector.eject(target)
            ejectedMediaIDs.insert(id)
            devices.removeAll { $0.mediaRegistryID == id }
            if selectedID == target.id { selectedID = devices.first?.id }
            ejectionFeedback = EjectionFeedback(title: "已安全推出“\(target.displayName)”", message: "现在可以拔下这块硬盘的连接线。", failed: false,
                receipt: DiskEjectionReceipt(targetRegistryID: id, otherConnectedRegistryIDs: Set(devices.compactMap(\.mediaRegistryID))))
        } catch {
            ejectionFeedback = EjectionFeedback(title: "“\(target.displayName)”未能安全推出", message: error.localizedDescription + " 请先不要拔线。", failed: true)
        }
        slowNotice.cancel(); ejectingDisk = nil; ejectionIsSlow = false
        // Catch mount/unmount notifications skipped while the operation was in flight.
        await refresh(force: false, showProgress: false)
    }
    func record(for disk: DiskDevice) -> DeviceRecord {
        guard let identity = disk.persistentIdentity else { return DeviceRecord() }
        return records[identity] ?? DeviceRecord()
    }
    func label(for disk: DiskDevice) -> DeviceLabel? {
        disk.labelIdentity.flatMap { labels[$0] }
    }
    func profile(for disk: DiskDevice) -> DeviceProfile {
        DeviceCatalog.profile(for: disk, label: label(for: disk))
    }
    func canEditLabel(_ target: LabelEditorTarget) -> Bool {
        labelsReadable && discoveryError == nil && (try? DeviceLabelBinding.target(identity: target.identity, devices: devices)) != nil
    }
    func saveLabel(_ text: String, source: LabelConfirmationSource, target: LabelEditorTarget, allowConflict: Bool) throws {
        guard labelsReadable else { throw DeviceLabelError.unreadable }
        guard discoveryError == nil else { throw DeviceLabelError.disconnected }
        let disk = try DeviceLabelBinding.target(identity: target.identity, devices: devices)
        let part = try PartNumber.validate(text, sanDisk: disk.isSanDisk)
        guard allowConflict || PartNumber.conflict(for: disk, partNumber: part) == nil else { throw DeviceLabelError.conflict }
        var updated = labels
        updated[disk.labelIdentity!] = try DeviceLabel(partNumber: part, source: source)
        try persistLabels(updated)
    }
    func removeLabel(target: LabelEditorTarget) throws {
        guard labelsReadable else { throw DeviceLabelError.unreadable }
        guard discoveryError == nil else { throw DeviceLabelError.disconnected }
        let disk = try DeviceLabelBinding.target(identity: target.identity, devices: devices)
        var updated = labels; updated.removeValue(forKey: disk.labelIdentity!)
        try persistLabels(updated)
    }
    private func persistLabels(_ updated: [String: DeviceLabel]) throws {
        // Capture previews never modify the user's confirmed labels.
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--capture=") }) else { return }
        do { try labelStore.save(updated); labels = updated; labelError = nil }
        catch { labelError = "补充型号或料号未能保存：\(error.localizedDescription)"; throw error }
    }
    func saveHistory() {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--capture=") }) else { return }
        guard historyReadable else { return }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: historyURL, options: .atomic)
            historyError = nil
        } catch { historyError = "历史记录未能保存：\(error.localizedDescription)" }
    }
    func export(_ disk: DiskDevice) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let serial = disk.snapshot.serial ?? disk.id
        let safeSerial = serial.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        panel.nameFieldStringValue = "硬盘报告-\(safeSerial)-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).txt"
        panel.title = "导出设备报告"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ReportBuilder.text(for: disk, benchmarks: record(for: disk).benchmarks, label: label(for: disk)).write(to: url, atomically: true, encoding: .utf8); notice = "设备报告已导出。" }
        catch { notice = "导出失败：\(error.localizedDescription)" }
    }
    func copyReport(_ disk: DiskDevice, raw: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw ? disk.snapshot.rawText : ReportBuilder.text(for: disk, benchmarks: record(for: disk).benchmarks, label: label(for: disk)), forType: .string)
        notice = raw ? "原始 SMART 报告已复制。" : "设备报告已复制。"
    }
    func openBenchmark() {
        guard let url = benchmarkAppURL else {
            notice = "尚未安装 AmorphousDiskMark。可通过测速页面的下载入口安装。"; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.notice = "打开测速工具失败：\(error.localizedDescription)" } }
        }
    }
    func importClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { notice = "剪贴板里没有文字成绩。请在 AmorphousDiskMark 窗口按 ⌘C 后重试。"; return }
        parseImport(text)
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attrs[.size] as? NSNumber)?.intValue ?? 0) < 100_000 else { throw BenchmarkImportError.invalid }
            parseImport(try String(contentsOf: url, encoding: .utf8))
        } catch { notice = error.localizedDescription }
    }
    private func parseImport(_ text: String) {
        do { importCandidate = try BenchmarkParser.parse(text) }
        catch { notice = error.localizedDescription }
    }
    func saveBenchmark(_ result: BenchmarkResult, to identity: String) {
        guard devices.contains(where: { $0.persistentIdentity == identity }) else { notice = "目标设备已断开或没有可靠的唯一身份，未保存此次成绩。"; return }
        var record = records[identity] ?? DeviceRecord()
        // 按完整原文去重，避免同一剪贴板成绩反复导入。
        guard !record.benchmarks.contains(where: { $0.rawText == result.rawText }) else { notice = "这份成绩已经保存，无需重复导入。"; importCandidate = nil; return }
        record.benchmarks.insert(result, at: 0); record.benchmarks = Array(record.benchmarks.prefix(30))
        records[identity] = record; saveHistory(); importCandidate = nil
        notice = historyError == nil ? "测速成绩已关联到所选硬盘。" : historyError
    }
}
