import SwiftUI
import AppKit
import DiskCore

struct SMARTDetailView: View {
    @EnvironmentObject var model: AppModel
    let disk: DiskDevice
    @ViewState private var query = ""
    @ViewState private var rawJSON = false
    var filtered: [SMARTField] {
        disk.snapshot.fields.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SMART 健康明细").font(.system(size: 17, weight: .semibold))
                    Text(disk.snapshot.explanation).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { model.copyReport(disk, raw: true) } label: { Label("复制原文", systemImage: "doc.on.doc") }.disabled(disk.snapshot.rawText.isEmpty)
            }
            if !disk.snapshot.fields.isEmpty {
                HStack(spacing: 10) {
                    Label("搜索指标", systemImage: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    TextField("", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
                        .accessibilityLabel("搜索 SMART 指标").help("输入指标名称、当前值或说明")
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("指标").frame(width: 170, alignment: .leading)
                        Text("当前值").frame(width: 142, alignment: .leading)
                        Text("说明").frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).padding(.vertical, 11).padding(.horizontal, 12).background(Palette.panel)
                    if filtered.isEmpty { Text("没有匹配的指标").foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(25) }
                    ForEach(filtered) { field in
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 0) {
                                Text(field.name).frame(width: 170, alignment: .leading)
                                Text(field.value).fontWeight(.medium).monospacedDigit().foregroundStyle(field.flagged ? Palette.health(.attention) : .primary).frame(width: 142, alignment: .leading).textSelection(.enabled)
                                Text(field.note).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                            }.font(.system(size: 12)).padding(.vertical, 11).padding(.horizontal, 12)
                                .accessibilityElement(children: .combine)
                            Divider().overlay(Palette.line)
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !disk.snapshot.attributes.isEmpty {
                DisclosureGroup("ATA 厂商原始属性（\(disk.snapshot.attributes.count) 项）") {
                    VStack(spacing: 0) {
                        ForEach(disk.snapshot.attributes) { field in
                            HStack(alignment: .top, spacing: 12) {
                                Text(field.id).monospacedDigit().foregroundStyle(Palette.muted).frame(width: 30, alignment: .leading)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(field.name).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    Text(field.note).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(field.value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: 220, alignment: .trailing)
                            }.padding(.vertical, 10)
                            Divider().overlay(Palette.line)
                        }
                    }.padding(.top, 10)
                    Text("Unknown 属性保留厂商原值，不猜测含义或单位。标准化值也不等同于健康百分比。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 10)
                }.font(.system(size: 13, weight: .medium))
            }
            DisclosureGroup("原始报告") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("报告格式", selection: $rawJSON) { Text("文本").tag(false); Text("JSON").tag(true) }.pickerStyle(.segmented).frame(width: 170)
                    ScrollView([.horizontal, .vertical]) {
                        Text(rawJSON ? disk.snapshot.rawJSON : disk.snapshot.rawText)
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.frame(height: 260).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                }.padding(.top, 10)
            }.font(.system(size: 13, weight: .medium))
        }
    }
}
