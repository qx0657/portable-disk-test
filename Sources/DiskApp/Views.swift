import SwiftUI
import AppKit
import Charts
import DiskCore

// 使用稳定的属性包装器，避免 SDK 27 的同名宏依赖完整 Xcode 插件。
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let ground = adaptive(0xFAFCFB, 0x18211E)
    static let sidebar = adaptive(0xEAF1EE, 0x111A17)
    static let panel = adaptive(0xF0F5F2, 0x202E28)
    static let accent = adaptive(0x246458, 0x81CBB5)
    static let muted = adaptive(0x50665E, 0xB0C4BA)
    static let line = adaptive(0xDCE6E0, 0x34453D)
    static let selected = adaptive(0x24574C, 0x2C6051)
    static func health(_ state: HealthState) -> Color {
        switch state {
        case .passed: return adaptive(0x286A49, 0x87D5A3)
        case .attention: return adaptive(0x956015, 0xF0C778)
        case .failed: return adaptive(0xB83D37, 0xFF9F98)
        case .unavailable: return muted
        }
    }
}

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reducedMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("移动硬盘测试").font(.system(size: 15, weight: .semibold))
                Text("\(model.devices.count) 台已连接").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small).accessibilityLabel("正在读取硬盘") }
                Button { Task { await model.refresh(force: true) } } label: { Label("重新扫描", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command).disabled(model.isRefreshing)
                Button { if let disk = model.selected { model.export(disk) } } label: { Label("导出报告", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: .command).disabled(model.selected == nil)
            }
            .controlSize(.regular).buttonStyle(.bordered)
            .padding(.leading, 92).padding(.trailing, 22).frame(height: 56)
            Divider().overlay(Palette.line)
            HStack(spacing: 0) {
                sidebar.frame(width: 232)
                Rectangle().fill(Palette.line).frame(width: 1)
                VStack(spacing: 0) {
                    if let error = model.discoveryError {
                        Label("扫描失败，以下可能是上次数据。\(error)", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(Palette.health(.attention))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Palette.panel)
                    }
                    if let disk = model.selected {
                        DeviceDetail(disk: disk).id(disk.identity)
                    } else if !model.hasScanned {
                        VStack(spacing: 18) { ProgressView(); Text("正在发现外接硬盘…").foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "externaldrive.badge.plus").font(.system(size: 42, weight: .light)).foregroundStyle(Palette.accent)
                            Text("连接一块移动硬盘").font(.system(size: 20, weight: .semibold)).foregroundStyle(.primary)
                            Text("通过 USB 或雷雳连接后，设备会自动出现在左侧。\n这里显示外接物理硬盘，不包含 Mac 内置盘和磁盘镜像。")
                                .font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 400)
                            Button("重新扫描") { Task { await model.refresh(force: true) } }.buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.ground).tint(Palette.accent)
        .animation(reducedMotion ? nil : .easeOut(duration: 0.16), value: model.selectedID)
        .sheet(item: $model.importCandidate) { result in ImportSheet(result: result).environmentObject(model) }
        .sheet(item: $model.labelEditor) { target in DeviceLabelEditor(target: target).environmentObject(model) }
        .alert("移动硬盘测试", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好", role: .cancel) { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("外接设备").font(.system(size: 12, weight: .semibold)); Spacer(); Text("\(model.devices.count)").monospacedDigit() }
                .foregroundStyle(Palette.muted).padding(.horizontal, 20).padding(.top, 23).padding(.bottom, 15)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(model.devices) { disk in
                        Button { model.selectedID = disk.id } label: {
                            SidebarDevice(disk: disk, selected: model.selectedID == disk.id)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(disk.displayName)，\(DiskFormat.bytes(disk.capacity))，\(disk.snapshot.health.title)")
                            .accessibilityAddTraits(model.selectedID == disk.id ? .isSelected : [])
                    }
                }.padding(.horizontal, 10)
            }
            VStack(alignment: .leading, spacing: 12) {
                Divider().overlay(Palette.line)
                Toggle("自动更新", isOn: $model.automatic).toggleStyle(.switch).controlSize(.small)
                Text(model.automatic ? "自动发现设备 · SMART 每 30 秒更新" : "自动更新已暂停，可手动重新扫描")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if let error = model.historyError {
                    Text(error).font(.system(size: 11)).foregroundStyle(Palette.health(.attention)).fixedSize(horizontal: false, vertical: true)
                }
                Text("本地读取 · 数据不上传").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(18)
        }.background(Palette.sidebar)
    }
}

struct SidebarDevice: View {
    let disk: DiskDevice
    let selected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "externaldrive.fill").font(.system(size: 25, weight: .light)).frame(width: 30).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                if disk.isSanDisk { BrandMark(brand: .sandisk, white: selected).frame(width: 86, height: 11, alignment: .leading) }
                Text(disk.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text([DiskFormat.bytes(disk.capacity), disk.persistentIdentity == nil ? disk.id : disk.solidState == true ? "SSD" : disk.solidState == false ? "HDD" : "外接磁盘"].joined(separator: " · "))
                    .font(.system(size: 11)).opacity(selected ? 0.86 : 1)
                HStack(spacing: 5) {
                    Circle().fill(selected ? Color.white : Palette.health(disk.snapshot.health)).frame(width: 5, height: 5)
                    Text(disk.snapshot.health == .passed ? "SMART 通过" : disk.snapshot.health == .unavailable ? "SMART 未提供" : "需要关注")
                        .font(.system(size: 11))
                }.opacity(selected ? 0.9 : 1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : Palette.muted)
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct BrandMark: View {
    let brand: DriveBrand
    var white = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        if brand == .sandisk,
           let url = Bundle.main.url(forResource: white || colorScheme == .dark ? "sandisk-white" : "sandisk-red", withExtension: "svg", subdirectory: "Brands"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("闪迪 SanDisk")
        } else {
            Text(brand.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(white ? Color.white : Palette.muted)
        }
    }
}

struct DeviceDetail: View {
    @EnvironmentObject var model: AppModel
    let disk: DiskDevice
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(systemName: "externaldrive.fill").font(.system(size: 41, weight: .light)).foregroundStyle(Palette.accent)
                    .frame(width: 70, height: 70).background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 7) {
                    Text(disk.model).font(.system(size: 23, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                    if disk.profile.brand != .unknown {
                        HStack(spacing: 12) {
                            BrandMark(brand: disk.profile.brand).frame(width: disk.isSanDisk ? 106 : 140, height: 15, alignment: .leading)
                        }
                    }
                    Text("\(DiskFormat.bytes(disk.capacity))   ·   \(disk.connection)   ·   /dev/\(disk.id)")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                Spacer(minLength: 4)
                HealthBadge(state: disk.snapshot.health)
            }.padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 22)
            HStack {
                Picker("设备信息分类", selection: $model.page) {
                    ForEach(DetailPage.allCases) { page in Text(page.rawValue).tag(page) }
                }.pickerStyle(.segmented).frame(width: 294).labelsHidden()
                Spacer()
                Text("更新于 \(disk.snapshot.date.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).monospacedDigit()
            }.padding(.horizontal, 28).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    switch model.page {
                    case .overview: OverviewView(disk: disk)
                    case .smart: SMARTDetailView(disk: disk)
                    case .speed: SpeedView(disk: disk)
                    }
                }.padding(.horizontal, 28).padding(.top, 2).padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct HealthBadge: View {
    let state: HealthState
    var body: some View {
        Label(state == .passed ? "检查通过" : state == .unavailable ? "未提供" : "需关注",
              systemImage: state == .passed ? "checkmark.seal.fill" : state == .unavailable ? "questionmark.circle" : "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.health(state))
            .padding(.horizontal, 11).padding(.vertical, 7).background(Palette.health(state).opacity(0.09), in: Capsule())
    }
}

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    let disk: DiskDevice
    var s: SMARTSnapshot { disk.snapshot }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: s.health == .passed ? "checkmark.circle.fill" : s.health == .unavailable ? "info.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.health(s.health))
                Text(s.health.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if s.partial { Text("部分数据未读取").font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }
            Text(s.explanation).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }
        HStack(alignment: .top, spacing: 0) {
            MetricView(title: "当前温度", value: s.temperature.map { DiskFormat.number($0) } ?? "—", unit: s.temperature != nil ? "°C" : "", note: "设备温度")
            metricDivider
            MetricView(title: "寿命消耗", value: s.percentageUsed.map { DiskFormat.number($0) } ?? "—", unit: s.percentageUsed != nil ? "%" : "", note: "固件估算")
            metricDivider
            MetricView(title: "累计写入", value: s.bytesWritten.map { DiskFormat.bytes($0) } ?? "—", unit: "", note: "主机写入量")
            metricDivider
            MetricView(title: "累计通电", value: s.hours.map { DiskFormat.integer($0) } ?? "—", unit: s.hours != nil ? "小时" : "", note: "设备累计计数")
        }.padding(.vertical, 19).padding(.horizontal, 8).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: "空间与分区", trailing: "\(disk.volumes.count) 个卷")
            if disk.volumes.isEmpty { Text("未发现可识别的卷。设备可能尚未分区，或文件系统未受支持。").font(.system(size: 12)).foregroundStyle(Palette.muted) }
            ForEach(disk.volumes) { volume in VolumeView(volume: volume) }
        }
        DeviceIdentitySection(disk: disk)
        let samples = model.record(for: disk).samples
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "最近温度", trailing: samples.count >= 2 ? "本机采集记录" : "开始记录")
            if samples.count >= 2 {
                Chart(samples) { sample in
                    LineMark(x: .value("时间", sample.date), y: .value("温度", sample.celsius)).foregroundStyle(Palette.accent).lineStyle(StrokeStyle(lineWidth: 2))
                }.chartYScale(domain: temperatureRange(samples)).chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }.frame(height: 90)
                    .accessibilityLabel("最近 \(samples.count) 次温度记录，当前 \(DiskFormat.number(s.temperature)) 摄氏度")
            } else {
                Text(disk.persistentIdentity == nil ? "当前设备缺少可靠的唯一身份，仅显示当前数据，不保存跨会话记录。" : "保持连接后，每 30 秒记录一次真实温度。不足两次时不绘制趋势。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
    }
    var metricDivider: some View { Rectangle().fill(Palette.line).frame(width: 1, height: 65).padding(.top, 6) }
    func temperatureRange(_ samples: [TemperatureSample]) -> ClosedRange<Double> {
        let minTemp = samples.map(\.celsius).min() ?? 20, maxTemp = samples.map(\.celsius).max() ?? 40
        return (minTemp - 3)...(maxTemp + 3)
    }
}

struct MetricView: View {
    let title: String; let value: String; let unit: String; let note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 26, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(unit).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }
            Text(note).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
    }
}

struct SectionTitle: View {
    let title: String
    var trailing = ""
    var body: some View { HStack { Text(title).font(.system(size: 14, weight: .semibold)); Spacer(); if !trailing.isEmpty { Text(trailing).font(.system(size: 11)).foregroundStyle(Palette.muted) } } }
}

struct InfoPair: View {
    let title: String; let value: String
    init(_ title: String, _ value: String) { self.title = title; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(width: 74, alignment: .leading)
            Text(value).font(.system(size: 12, weight: .medium)).textSelection(.enabled).lineLimit(2)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VolumeView: View {
    let volume: DiskVolume
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(volume.name, systemImage: "internaldrive").font(.system(size: 12, weight: .medium))
                Text(volume.filesystem).font(.system(size: 11)).foregroundStyle(Palette.muted)
                if !volume.writable { Text("只读").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                Spacer()
                Text(DiskFormat.bytes(volume.capacity)).font(.system(size: 12)).monospacedDigit()
                if let mount = volume.mountPoint {
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: mount)) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.plain).foregroundStyle(Palette.accent).help("在访达中打开 \(volume.name)")
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.line)
                    if let used = volume.used, volume.capacity > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.accent)
                            .frame(width: max(used > 0 ? 3 : 0, geometry.size.width * min(1, used / volume.capacity)))
                    }
                }
            }.frame(height: 6).accessibilityLabel("已用 \(DiskFormat.bytes(volume.used))，可用 \(DiskFormat.bytes(volume.free))")
            HStack {
                Text(volume.free != nil ? "已用 \(DiskFormat.bytes(volume.used)) · 可用 \(DiskFormat.bytes(volume.free))" : "空间统计未提供")
                Spacer()
                Text(volume.mountPoint == nil ? "未挂载" : volume.id)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}
