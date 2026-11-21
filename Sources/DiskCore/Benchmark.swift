import Foundation

public struct BenchmarkRow: Identifiable, Codable, Sendable {
    public var id: String
    public var name: String
    public var queueDepth: Int
    public var read: Double
    public var write: Double
}

public struct BenchmarkResult: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var importedAt = Date()
    public var measuredAt: Date?
    public var deviceName: String
    public var volumeName: String
    public var settings: String
    public var rows: [BenchmarkRow]
    public var rawText: String
}

public enum BenchmarkImportError: LocalizedError {
    case invalid
    public var errorDescription: String? {
        "没有识别到完整的 AmorphousDiskMark 文字成绩。请在测速完成后选择其窗口，按 ⌘C 复制成绩，再回来导入。图片不能直接导入。"
    }
}

public enum BenchmarkParser {
    public static func parse(_ text: String) throws -> BenchmarkResult {
        guard text.count < 100_000 else { throw BenchmarkImportError.invalid }
        let pattern = #"(?im)^\s*(Sequential|Random)\s+(Read|Write)\s+(1MiB|4KiB)\s*\(QD=\s*(\d+)\)\s*:\s*([\d,]+(?:\.\d+)?)\s*MB/s\b"#
        let expression = try NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var values: [String: (String, Int, [String: Double])] = [:]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let kind = ns.substring(with: match.range(at: 1))
            let action = ns.substring(with: match.range(at: 2)).lowercased()
            let block = ns.substring(with: match.range(at: 3))
            let qd = Int(ns.substring(with: match.range(at: 4))) ?? 0
            guard qd > 0, qd <= 1024, let speed = Double(ns.substring(with: match.range(at: 5)).replacingOccurrences(of: ",", with: "")),
                  speed.isFinite, speed > 0, speed < 1_000_000 else { throw BenchmarkImportError.invalid }
            let key = "\(kind)-\(qd)"
            var item = values[key] ?? (kind == "Sequential" ? "顺序 \(block)" : "随机 \(block)", qd, [:])
            guard item.2[action] == nil else { throw BenchmarkImportError.invalid }
            item.2[action] = speed; values[key] = item
        }
        guard values.count == 4, values.values.allSatisfy({ $0.2.count == 2 }) else { throw BenchmarkImportError.invalid }
        func metadata(_ key: String) -> String {
            let regex = try! NSRegularExpression(pattern: "(?im)^\\s*" + key + "\\s*:\\s*(.+)$")
            guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return "" }
            return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rows = values.map { key, item in
            BenchmarkRow(id: key, name: item.0, queueDepth: item.1, read: item.2["read"]!, write: item.2["write"]!)
        }.sorted {
            let a = $0.id.hasPrefix("Sequential"), b = $1.id.hasPrefix("Sequential")
            return a != b ? a : $0.queueDepth > $1.queueDepth
        }
        let date = ISO8601DateFormatter().date(from: metadata("Date"))
        return BenchmarkResult(measuredAt: date, deviceName: metadata("Device"), volumeName: metadata("Volume"),
                               settings: metadata("Test"), rows: rows, rawText: text)
    }
}

public struct TemperatureSample: Codable, Identifiable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var celsius: Double
    public init(date: Date, celsius: Double) { self.date = date; self.celsius = celsius }
}

public struct DeviceRecord: Codable, Sendable {
    public var firstSeen: Date
    public var samples: [TemperatureSample] = []
    public var benchmarks: [BenchmarkResult] = []
    public init(firstSeen: Date = Date()) { self.firstSeen = firstSeen }
}

public struct ReportBuilder {
    public static func text(for device: DiskDevice, benchmarks: [BenchmarkResult] = [], label: DeviceLabel? = nil) -> String {
        let s = device.snapshot
        let profile = DeviceCatalog.profile(for: device, label: label)
        var lines = ["移动硬盘测试 · 设备报告", "采集时间：\(s.date.formatted())", "电脑：\(Host.current().localizedName ?? "Mac")",
                     "型号：\(device.model)", "设备号：/dev/\(device.id)", "序列号：\(s.serial ?? "未提供")",
                     "品牌：\(profile.brand.title)", "产品系列：\(profile.seriesLabel ?? "未确认")",
                     "完整料号：\(profile.partNumber ?? "设备未提供")", "料号来源：\(profile.partNumberSource?.title ?? "设备未提供，尚未补充")",
                     "系列依据：\(profile.basis ?? "设备报告的原始型号名称，不推算销售型号")",
                     "固件：\(s.firmware ?? "未提供")", "容量：\(DiskFormat.bytes(device.capacity))", "连接：\(device.connection)",
                     "健康：\(s.health.title)", s.explanation, "", "SMART 指标"]
        if let url = profile.sourceURL { lines.insert("官方参考：\(url.absoluteString)", at: 11) }
        if let label {
            lines.insert(contentsOf: ["本地补充料号：\(label.partNumber)（\(label.source.title)）", "确认时间：\(label.confirmedAt.formatted())"], at: 11)
        }
        lines += s.fields.map { "\($0.name)：\($0.value)\($0.note.isEmpty ? "" : "（\($0.note)）")" }
        lines += ["", "卷与分区"]
        lines += device.volumes.map { "\($0.name) · \($0.filesystem) · \(DiskFormat.bytes($0.capacity)) · 可用 \(DiskFormat.bytes($0.free)) · \($0.mountPoint ?? "未挂载")" }
        for result in benchmarks {
            lines += ["", "AmorphousDiskMark 测速记录（由用户确认关联）", "导入时间：\(result.importedAt.formatted())", result.rawText]
        }
        lines += ["", "原始 SMART 输出", s.rawText, "", "原始 SMART JSON", s.rawJSON]
        return lines.joined(separator: "\n")
    }
}
