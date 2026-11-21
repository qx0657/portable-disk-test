import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DiskCore

struct DeviceIdentitySection: View {
    @EnvironmentObject var model: AppModel
    let disk: DiskDevice
    private var profile: DeviceProfile { model.profile(for: disk) }
    private var label: DeviceLabel? { model.label(for: disk) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("设备信息").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { model.labelEditor = LabelEditorTarget(disk: disk) } label: {
                    Label(label == nil ? "补充料号…" : "编辑补充…", systemImage: "pencil")
                }.buttonStyle(.borderless).font(.system(size: 12))
                    .help("手动填写或识别标签照片，确认后保存在这台 Mac 上")
            }
            identityRow("产品系列", value: profile.series ?? "未确认", source: profile.seriesSource)
            identityRow("完整料号", value: profile.partNumber ?? "设备未提供", source: profile.partNumberSource)
            Grid(alignment: .leading, horizontalSpacing: 34, verticalSpacing: 15) {
                GridRow { InfoPair("序列号", disk.snapshot.serial ?? "未提供"); InfoPair("固件版本", disk.snapshot.firmware ?? "未提供") }
                GridRow { InfoPair("品牌", profile.brand.title); InfoPair("介质类型", disk.solidState == true ? "固态硬盘（SSD）" : disk.solidState == false ? "机械硬盘（HDD）" : "未提供") }
                GridRow { InfoPair("连接方式", disk.connection); InfoPair("通电次数", disk.snapshot.powerCycles.map { DiskFormat.integer($0) + " 次" } ?? "未提供") }
                GridRow { InfoPair("累计读取", DiskFormat.bytes(disk.snapshot.bytesRead)); InfoPair("非正常关机", disk.snapshot.unsafeShutdowns.map { DiskFormat.integer($0) + " 次（历史累计）" } ?? "未提供") }
                GridRow { InfoPair("介质错误", DiskFormat.integer(disk.snapshot.mediaErrors)); Color.clear.frame(height: 1) }
            }
            if let error = model.labelError {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11))
                    .foregroundStyle(Palette.health(.attention)).fixedSize(horizontal: false, vertical: true)
            }
            if let label, let warning = PartNumber.conflict(for: disk, partNumber: label.partNumber) {
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 11))
                    .foregroundStyle(Palette.health(.attention)).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("识别依据与补充记录") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.basis ?? "上方 Model 为设备实际返回的名称。当前没有可靠的产品系列匹配依据，完整料号可从盘身标签补充。")
                    if let url = profile.sourceURL { Link("查看闪迪官方产品资料", destination: url) }
                    if let label {
                        Text("本地补充：\(label.partNumber) · \(label.source.title) · \(label.confirmedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Text("补充信息只保存在这台 Mac 上，不修改设备报告的 Model，也不写入硬盘。")
                }.fixedSize(horizontal: false, vertical: true).padding(.top, 6).textSelection(.enabled)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
    private func identityRow(_ title: String, value: String, source: DeviceIdentitySource?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(width: 74, alignment: .leading)
            Text(value).font(.system(size: 12, weight: .medium)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let source { Text(source.title).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

struct DeviceLabelEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    let target: LabelEditorTarget
    @ViewState private var partNumber = ""
    @ViewState private var photoURL: URL?
    @ViewState private var photoRevision = 0
    @ViewState private var photoTask: Task<Void, Never>?
    @ViewState private var candidates: [String] = []
    @ViewState private var isRecognizing = false
    @ViewState private var photoError: String?
    @ViewState private var saveError: String?
    @ViewState private var confirmedConflict = false
    @ViewState private var removing = false
    @ViewState private var initialLabel: DeviceLabel?
    @ViewState private var initialized = false
    private var validNumber: String? { try? PartNumber.validate(partNumber, sanDisk: target.disk.isSanDisk) }
    private var conflict: String? {
        let disk = (try? DeviceLabelBinding.target(identity: target.identity, devices: model.devices)) ?? target.disk
        return validNumber.flatMap { PartNumber.conflict(for: disk, partNumber: $0) }
    }
    private var live: Bool { model.canEditLabel(target) }
    private var source: LabelConfirmationSource {
        if photoURL != nil && candidates.contains(PartNumber.normalize(partNumber)) { return .photo }
        if let initialLabel, initialLabel.partNumber == PartNumber.normalize(partNumber) { return initialLabel.source }
        return .manual
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("补充完整料号").font(.system(size: 20, weight: .semibold))
                Text("从盘身标签填写或识别，核对后关联到下面这块硬盘。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(target.disk.model).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(DiskFormat.bytes(target.disk.capacity)) · 绑定序列号：\(target.disk.hardware?.serialNumber ?? target.disk.snapshot.serial ?? "未提供")")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
               VStack(alignment: .leading, spacing: 9) {
                Text("完整料号 / P/N").font(.system(size: 12, weight: .medium))
                TextField(target.disk.isSanDisk ? "例如 SDSSDE82-4T00-G25" : "填写盘身上的完整料号", text: $partNumber)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13)).focused($fieldFocused)
                    .accessibilityLabel("完整料号")
                    .onChange(of: partNumber) { _, _ in saveError = nil; confirmedConflict = false }
                Text("请照抄盘身完整 P/N，不要填写产品名称或序列号。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                HStack(spacing: 12) {
                    Button { choosePhoto() } label: { Label("从标签照片识别…", systemImage: "photo") }
                        .buttonStyle(.bordered).disabled(isRecognizing)
                    if isRecognizing { ProgressView().controlSize(.small); Text("正在本地识别…").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    else { Text("照片不上传，也不保存副本").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }.padding(.top, 3)
                if !target.disk.isSanDisk {
                    Text("照片识别目前支持闪迪 SDSSDE 料号，其他品牌请手动填写。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            if let photoURL {
                HStack(alignment: .top, spacing: 14) {
                    if let image = NSImage(contentsOf: photoURL) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 112, height: 76)
                            .accessibilityLabel("所选标签照片")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(photoURL.lastPathComponent).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                        if candidates.count > 1 {
                            Text("识别到多个料号，请选择与此设备对应的一项：").font(.system(size: 11))
                            ForEach(candidates, id: \.self) { value in
                                Button(value) { partNumber = value }.buttonStyle(.borderless).font(.system(size: 12))
                            }
                        } else if !candidates.isEmpty {
                            Text("识别结果已填入，请对照标签核对字符。")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let photoError { message(photoError, symbol: "info.circle") }
            if !live { message(model.labelError ?? (target.identity == nil ? DeviceLabelError.noIdentity.localizedDescription : DeviceLabelError.disconnected.localizedDescription), symbol: "exclamationmark.triangle") }
            if let conflict {
                VStack(alignment: .leading, spacing: 8) {
                    message(conflict, symbol: "exclamationmark.triangle")
                    Toggle("我已核对目标设备和标签，仍保存此补充料号", isOn: $confirmedConflict).font(.system(size: 12))
                }
            }
            if let saveError { message(saveError, symbol: "exclamationmark.triangle") }
            if !partNumber.isEmpty && validNumber == nil && !fieldFocused {
                message(validationMessage(), symbol: "info.circle")
            }
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            HStack {
                if initialLabel != nil {
                    Button("移除补充…", role: .destructive) { removing = true }.buttonStyle(.borderless).disabled(!live)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确认并保存") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validNumber == nil || !live || isRecognizing || (conflict != nil && !confirmedConflict))
            }.padding(.top, 4)
            Text("保存来源：\(source.title) · 仅在这台 Mac 上记住；不会上传序列号。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        .padding(28).frame(width: 620, height: photoURL != nil ? 600 : (conflict != nil || !live || saveError != nil ? 520 : 440))
        .background(Palette.ground).tint(Palette.accent)
        .onAppear {
            guard !initialized else { return }; initialized = true
            initialLabel = model.label(for: target.disk); partNumber = initialLabel?.partNumber ?? ""
            let args = ProcessInfo.processInfo.arguments
            if args.contains(where: { $0.hasPrefix("--capture=") }) {
                if let photo = args.first(where: { $0.hasPrefix("--label-photo-preview=") })?.dropFirst("--label-photo-preview=".count) {
                    photoURL = URL(fileURLWithPath: String(photo)); photoRevision += 1
                }
                if let number = args.first(where: { $0.hasPrefix("--label-number-preview=") })?.dropFirst("--label-number-preview=".count) {
                    partNumber = String(number)
                }
            }
            fieldFocused = true
            if photoURL != nil { startRecognition() }
        }
        .onDisappear { photoTask?.cancel(); model.isRecognizingLabelPhoto = false }
        .confirmationDialog("移除此设备的补充料号？", isPresented: $removing, titleVisibility: .visible) {
            Button("移除补充", role: .destructive) {
                do { try model.removeLabel(target: target); dismiss() } catch { saveError = error.localizedDescription }
            }
        } message: { Text("设备报告的名称、SMART 和测速记录会保留。") }
    }
    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12)).foregroundStyle(Palette.health(.attention))
            .fixedSize(horizontal: false, vertical: true)
    }
    private func validationMessage() -> String {
        do { _ = try PartNumber.validate(partNumber, sanDisk: target.disk.isSanDisk); return "" }
        catch { return error.localizedDescription }
    }
    private func choosePhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.title = "选择硬盘标签照片"
        panel.message = "请使用能清楚看到完整 P/N 的标签近照；照片只在本地识别。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        candidates = []; photoError = nil; saveError = nil; photoURL = url; photoRevision += 1
        startRecognition()
    }
    private func startRecognition() {
        photoTask?.cancel()
        isRecognizing = true; model.isRecognizingLabelPhoto = true
        photoTask = Task { await recognizePhoto() }
    }
    private func recognizePhoto() async {
        guard let url = photoURL else { return }
        let revision = photoRevision
        isRecognizing = true; model.isRecognizingLabelPhoto = true
        defer { if photoRevision == revision { isRecognizing = false; model.isRecognizingLabelPhoto = false } }
        do {
            let result = try await LabelPhotoReader.recognizeAsync(url: url)
            guard !Task.isCancelled, photoRevision == revision else { return }
            candidates = result
            if result.count == 1 { partNumber = result[0] }
        } catch {
            guard !Task.isCancelled, photoRevision == revision else { return }
            photoError = error.localizedDescription
        }
    }
    private func save() {
        do {
            try model.saveLabel(partNumber, source: source, target: target, allowConflict: confirmedConflict)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
