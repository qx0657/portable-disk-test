import Foundation

public enum LabelConfirmationSource: String, Codable, Sendable {
    case manual, photo
    public var title: String { self == .photo ? "标签确认" : "手动确认" }
}

public struct DeviceLabel: Codable, Equatable, Sendable {
    // Keep the stored key compatible: a value may be a label Model or a sales P/N.
    public var partNumber: String
    public var source: LabelConfirmationSource
    public var confirmedAt: Date
    public init(partNumber: String, source: LabelConfirmationSource, confirmedAt: Date = Date()) throws {
        self.partNumber = try PartNumber.validate(partNumber)
        self.source = source; self.confirmedAt = confirmedAt
    }
}

public enum DeviceLabelError: LocalizedError {
    case invalidNumber, invalidSanDisk, noIdentity, disconnected, unreadable, invalidArchive, conflict
    public var errorDescription: String? {
        switch self {
        case .invalidNumber: return "请输入 3–96 位型号或料号，包含字母和数字；可使用 - . _ /，不包含空格。"
        case .invalidSanDisk: return "请输入含容量的盘身型号，例如 SDSSDE82-4T00；标签有后缀时可一并填写，不要只写 E82。"
        case .noIdentity: return "设备缺少可靠且唯一的序列号，暂不能保存补充信息。"
        case .disconnected: return "目标设备已断开、身份发生变化或扫描未成功。请重新扫描后再保存。"
        case .unreadable: return "补充信息文件未能读取，原文件已保留。请重新打开软件后重试。"
        case .invalidArchive: return "补充信息格式无法识别，原文件已保留。"
        case .conflict: return "补充型号或料号与当前设备信息不一致，请核对后勾选确认。"
        }
    }
}

public enum PartNumber {
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "[‐‑‒–—−﹣－]", with: "-", options: .regularExpression)
    }
    public static func validate(_ text: String, sanDisk: Bool = false) throws -> String {
        let part = normalize(text)
        guard part.count >= 3, part.count <= 96,
              part.range(of: #"^[A-Z0-9][A-Z0-9._/\-]*[A-Z0-9]$"#, options: .regularExpression) != nil,
              part.contains(where: { $0.isASCII && $0.isLetter }),
              part.contains(where: { $0.isASCII && $0.isNumber }) else { throw DeviceLabelError.invalidNumber }
        if sanDisk {
            let complete = part.hasPrefix("SDSSDE") ? sanDiskCode(part) != nil :
                part.range(of: #"^SD[A-Z0-9]{4,12}-(?:[0-9]{1,2}T[0-9]{2}|[0-9]{3,4}G)(?:-[A-Z0-9]{2,8})?$"#, options: .regularExpression) != nil
            guard complete else { throw DeviceLabelError.invalidSanDisk }
        }
        return part
    }
    public static func sanDiskCode(_ text: String) -> String? {
        let part = normalize(text)
        // A label Model with a capacity is valid by itself. Never invent a SKU suffix.
        return part.range(of: #"^SDSSDE[0-9][A-Z0-9]{1,3}-(?:[0-9]{1,2}T[0-9]{2}|[0-9]{3,4}G)(?:-[A-Z0-9]{2,8})?$"#, options: .regularExpression) != nil ? part : nil
    }
    public static func sanDiskRetail(_ text: String) -> String? {
        guard let code = sanDiskCode(text), code.split(separator: "-").count == 3 else { return nil }
        return code
    }
    public static func baseModel(_ text: String) -> String? {
        guard let code = sanDiskCode(text) else { return nil }
        return code.split(separator: "-").prefix(2).joined(separator: "-")
    }
    public static func sanDiskSeries(_ text: String) -> String? {
        guard let part = sanDiskCode(text) else { return nil }
        return "E" + part.dropFirst(6).prefix(while: { $0 != "-" })
    }
    public static func photoCandidates(in lines: [String]) -> [String] {
        // Joining allows a wrapped label, but never substitutes O/0, I/1 or other ambiguous glyphs.
        let text = normalize(lines.joined(separator: "\n"))
        let pattern = #"(?<![A-Z0-9])SDSSDE[0-9][A-Z0-9]{1,3}\s*-\s*(?:[0-9]{1,2}T[0-9]{2}|[0-9]{3,4}G)(?:\s*-\s*[A-Z0-9]{2,8})?(?![A-Z0-9]|\s*-)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            let value = ns.substring(with: $0.range).replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
            guard let part = sanDiskCode(value), seen.insert(part).inserted else { return nil }
            return part
        }
    }
    public static func conflict(for disk: DiskDevice, partNumber: String) -> String? {
        let actual = disk.profile
        let entered = normalize(partNumber)
        if let provided = actual.reportedPartNumber, provided != entered {
            let reportedBase = baseModel(provided), enteredBase = baseModel(entered)
            let sameModelWithOptionalSuffix = reportedBase != nil && reportedBase == enteredBase
                && (provided == reportedBase || entered == enteredBase)
            if !sameModelWithOptionalSuffix {
                return "补充型号或料号与设备直接报告的 \(provided) 不一致。保存后会同时保留来源，设备报告值优先展示。"
            }
        }
        if let series = sanDiskSeries(partNumber), let expected = actual.series, expected != series {
            return "填写的代码属于 \(series)，当前设备的产品系列为 \(expected)（\(actual.seriesSource?.title ?? "设备报告")）。请核对目标设备与标签。"
        }
        return nil
    }
}

public struct DeviceLabelStore: Sendable {
    public let url: URL
    private struct Archive: Codable { var version = 1; var labels: [String: DeviceLabel] }
    public init(url: URL) { self.url = url }
    public func load() throws -> [String: DeviceLabel] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else { throw DeviceLabelError.invalidArchive }
        for (key, value) in archive.labels {
            guard key.hasPrefix("hardware:"), (try? PartNumber.validate(value.partNumber)) == value.partNumber else {
                throw DeviceLabelError.invalidArchive
            }
        }
        return archive.labels
    }
    public func save(_ labels: [String: DeviceLabel]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Archive(labels: labels)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum DeviceLabelBinding {
    public static func target(identity: String?, devices: [DiskDevice]) throws -> DiskDevice {
        guard let identity else { throw DeviceLabelError.noIdentity }
        let matches = devices.filter { $0.labelIdentity == identity }
        guard matches.count == 1, let disk = matches.first else { throw DeviceLabelError.disconnected }
        return disk
    }
}
