import SwiftUI
import AppKit
import DiskCore

struct SpeedView: View {
    @EnvironmentObject var model: AppModel
    let disk: DiskDevice
    @ViewState private var volumeID = ""
    var purpose: BenchmarkPurpose { model.benchmarkPurpose }
    var volumes: [DiskVolume] { disk.volumes.filter { $0.mountPoint != nil } }
    var selectedVolume: DiskVolume? { volumes.first { $0.id == volumeID } ?? volumes.first }
    var results: [BenchmarkResult] { model.record(for: disk).benchmarks }
    var advice: BenchmarkAdvice { BenchmarkAdvice.recommend(for: disk, volume: selectedVolume, purpose: purpose) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("让专业工具负责测速").font(.system(size: 19, weight: .semibold))
                    Text("使用 AmorphousDiskMark 测量读写速度，回到这里保存成绩，与这块盘的 SMART 一起查看。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                }
                Spacer()
                Image(systemName: "speedometer").font(.system(size: 34, weight: .light)).foregroundStyle(Palette.accent).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("测速准备").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(model.benchmarkAppURL == nil ? "测速工具未安装" : "AmorphousDiskMark 已安装")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("目标卷").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(width: 58, alignment: .leading)
                    if volumes.count > 1 {
                        Picker("目标卷", selection: $volumeID) { ForEach(volumes) { v in Text(v.name).tag(v.id) } }.labelsHidden().frame(maxWidth: 230)
                    } else {
                        Text(selectedVolume?.name ?? "没有已挂载的卷").font(.system(size: 13, weight: .medium))
                    }
                    Spacer()
                    Button("复制卷名") {
                        if let name = selectedVolume?.name { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(name, forType: .string) }
                    }.disabled(selectedVolume == nil)
                }
                HStack(spacing: 16) {
                    Text("测速目的").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(width: 58, alignment: .leading)
                    Picker("测速目的", selection: $model.benchmarkPurpose) {
                        ForEach(BenchmarkPurpose.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 350)
                    Spacer()
                }
                HStack(spacing: 16) {
                    Text("建议参数").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(width: 58, alignment: .leading)
                    Text(advice.parameterLabel).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    Spacer()
                }
                Text(advice.reason).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                Text(advice.scope).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text("打开后请手动选择上面的目标卷和参数，再点击 All。当前版本没有可供本应用可靠指定目标的公开启动接口。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                HStack(spacing: 12) {
                    if model.benchmarkAppURL != nil {
                        Button { model.openBenchmark() } label: { Label("打开 AmorphousDiskMark", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(.borderedProminent).disabled(advice.blockedReason != nil)
                    } else {
                        Link(destination: URL(string: "https://apps.apple.com/app/amorphousdiskmark/id1168254295")!) {
                            Label("在 App Store 获取测速工具", systemImage: "arrow.down.app")
                        }.buttonStyle(.borderedProminent)
                    }
                }
                if let reason = advice.blockedReason { Label(reason, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(Palette.health(.attention)) }
            }.padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("导入测速成绩").font(.system(size: 14, weight: .semibold))
                    Text("测完后，在 AmorphousDiskMark 窗口按 ⌘C 复制文字成绩。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Menu {
                    Button("从剪贴板导入") { model.importClipboard() }
                    Button("从文本文件导入…") { model.importFile() }
                } label: { Label("导入成绩", systemImage: "square.and.arrow.down") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            if let latest = results.first {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("最近一次成绩").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text((latest.measuredAt ?? latest.importedAt).formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    BenchmarkTable(result: latest)
                    Text(latest.settings.isEmpty ? "来源：AmorphousDiskMark · 设备归属由导入时确认" : latest.settings)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                if results.count > 1 {
                    DisclosureGroup("更早的成绩（\(results.count - 1) 次）") {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(results.dropFirst())) { item in
                                Text((item.measuredAt ?? item.importedAt).formatted()).font(.system(size: 12, weight: .medium))
                                BenchmarkTable(result: item)
                            }
                        }.padding(.top, 12)
                    }.font(.system(size: 13))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有导入测速成绩").font(.system(size: 13, weight: .medium))
                    Text(disk.persistentIdentity == nil ? "这块设备缺少可靠唯一标识，或标识与另一台设备重复。可以打开工具测速，但无法为它保存历史成绩。" : "成绩保存在当前 Mac，按序列号或唯一卷标识关联。导入前会显示型号和目标设备，避免多盘时串盘。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 10)
            }
            Text("测速会产生实际读写，测试文件大小不等于总写入量。本应用不会自动启动写入；导入也不会操作硬盘。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Text("同一块盘前后对比请保持参数一致；跨设备横向比较时，也应手动统一参数。").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.onAppear { volumeID = volumes.first?.id ?? "" }
    }
}

struct BenchmarkTable: View {
    let result: BenchmarkResult
    let writeColor = Palette.adaptive(0x486E8B, 0x91B7D5)
    var maximum: Double { result.rows.flatMap { [$0.read, $0.write] }.max() ?? 1 }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("项目").frame(width: 145, alignment: .leading)
                Text("读取 MB/s").frame(maxWidth: .infinity, alignment: .leading)
                Text("写入 MB/s").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).padding(.bottom, 10)
            ForEach(result.rows) { row in
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.name).font(.system(size: 12, weight: .medium))
                        Text("QD \(row.queueDepth)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }.frame(width: 129, alignment: .leading)
                    speedCell(row.read, color: Palette.accent)
                    speedCell(row.write, color: writeColor)
                }.padding(.vertical, 12).accessibilityElement(children: .combine)
                Divider().overlay(Palette.line)
            }
        }
    }
    func speedCell(_ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value.formatted(.number.precision(.fractionLength(2)))).font(.system(size: 21, weight: .semibold)).monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.line)
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: geometry.size.width * value / max(1, maximum))
                }
            }.frame(height: 4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ImportSheet: View {
    @EnvironmentObject var model: AppModel
    let result: BenchmarkResult
    @ViewState private var target = ""
    var selected: DiskDevice? { model.devices.first { $0.identity == target } }
    var mismatch: Bool {
        guard let selected else { return false }
        return !result.deviceName.isEmpty && result.deviceName.caseInsensitiveCompare(selected.model) != .orderedSame
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认成绩属于哪块硬盘").font(.system(size: 20, weight: .semibold))
            Text("测速结果不包含可靠的硬盘序列号。请选择设备后保存，应用不会自动猜测归属。")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 8) {
                Text("成绩型号：\(result.deviceName.isEmpty ? "未提供" : result.deviceName)")
                Text("成绩卷名：\(result.volumeName.isEmpty ? "未提供" : result.volumeName)")
            }.font(.system(size: 12)).textSelection(.enabled)
            Picker("保存到", selection: $target) {
                Text("请选择目标硬盘").tag("")
                ForEach(model.devices.filter { $0.persistentIdentity != nil }) { disk in
                    Text("\(disk.displayName) · \(DiskFormat.bytes(disk.capacity)) · \(disk.snapshot.serial ?? disk.id)").tag(disk.identity)
                }
            }
            if mismatch { Label("成绩型号与目标设备不同，请核对后再保存。", systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Palette.health(.attention)) }
            BenchmarkTable(result: result)
            HStack {
                Button("取消", role: .cancel) { model.importCandidate = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认并保存") { model.saveBenchmark(result, to: target) }.buttonStyle(.borderedProminent).disabled(selected == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 610).background(Palette.ground).tint(Palette.accent)
        .onAppear { target = model.selected?.persistentIdentity ?? "" }
    }
}
