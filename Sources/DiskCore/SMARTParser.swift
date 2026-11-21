import Foundation

public enum SMARTParser {
    public static func parse(_ data: Data, status: Int32 = 0, stderr: String = "") -> SMARTSnapshot {
        var s = SMARTSnapshot()
        s.rawJSON = String(data: data, encoding: .utf8) ?? ""
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            s.explanation = stderr.isEmpty ? "SMART 读取未返回有效数据，请刷新重试。" : stderr
            return s
        }
        let tool = j.dict("smartctl")
        let exit = Int(tool.number("exit_status") ?? Double(status))
        s.rawText = (tool["output"] as? [String])?.joined(separator: "\n") ?? s.rawJSON
        s.model = j.string("model_name"); s.serial = j.string("serial_number"); s.firmware = j.string("firmware_version")
        s.protocolName = j.dict("device").string("protocol")
        s.temperature = j.dict("temperature").number("current")
        s.temperatureWarning = j.dict("temperature").number("op_limit_max")
        s.hours = j.dict("power_on_time").number("hours")
        s.powerCycles = j.number("power_cycle_count")
        s.percentageUsed = j.dict("endurance_used").number("current_percent")
        s.spare = j.dict("spare_available").number("current_percent")
        let nvme = j.dict("nvme_smart_health_information_log")
        let ata = j.dict("ata_smart_attributes").array("table")
        let stats = j.dict("ata_device_statistics").array("pages").flatMap { $0.array("table") }
        let validStats = stats.filter { $0.dict("flags")["valid"] as? Bool != false }
        func statistic(_ name: String) -> Double? { validStats.first { $0.string("name") == name }?.number("value") }
        func attribute(_ id: Int) -> Double? { ata.first { $0.number("id") == Double(id) }?.dict("raw").number("value") }
        if !nvme.isEmpty {
            s.bytesRead = nvme.number("data_units_read").map { $0 * 512_000 }
            s.bytesWritten = nvme.number("data_units_written").map { $0 * 512_000 }
            s.unsafeShutdowns = nvme.number("unsafe_shutdowns")
            s.mediaErrors = nvme.number("media_errors")
            s.errorLogCount = nvme.number("num_err_log_entries")
            s.temperature = s.temperature ?? nvme.number("temperature")
            s.percentageUsed = s.percentageUsed ?? nvme.number("percentage_used")
            s.hours = s.hours ?? nvme.number("power_on_hours")
            s.powerCycles = s.powerCycles ?? nvme.number("power_cycles")
        } else if !ata.isEmpty {
            // ATA 241/242 的单位随厂商而异。只换算标准设备统计，避免把 GB 误认作扇区。
            let sector = j.number("logical_block_size") ?? 512
            s.bytesRead = statistic("Logical Sectors Read").map { $0 * sector }
            s.bytesWritten = statistic("Logical Sectors Written").map { $0 * sector }
            s.percentageUsed = s.percentageUsed ?? statistic("Percentage Used Endurance Indicator")
            s.mediaErrors = attribute(187)
            s.errorLogCount = j.dict("ata_smart_error_log").dict("summary").number("count")
        }
        let passed = j.dict("smart_status")["passed"] as? Bool
        let hasHealth = passed != nil || !nvme.isEmpty || !ata.isEmpty
        s.partial = hasHealth && (exit & 7 != 0)
        let messages = tool.array("messages").compactMap { $0.string("string") }.joined(separator: "\n")
        let diagnostic = [messages, stderr, s.rawText].joined(separator: "\n").lowercased()
        let permissionDenied = diagnostic.contains("permission denied") || diagnostic.contains("operation not permitted") || diagnostic.contains("insufficient permission")
        let ioFailure = diagnostic.contains("input/output error") || diagnostic.contains("i/o error") || diagnostic.contains("device i/o")
        let errorLines = s.rawText.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains("failed") || $0.localizedCaseInsensitiveContains("error:") }
        let failureDiagnostic = ([messages, stderr] + errorLines.map(String.init)).joined(separator: "\n").lowercased()
        let explicitlyUnsupported = failureDiagnostic.contains("not implemented") || failureDiagnostic.contains("not supported") || failureDiagnostic.contains("unsupported")
        if s.partial {
            if permissionDenied { s.partialDescription = "部分数据因访问权限不足未能读取，请查看原始报告。" }
            else if ioFailure { s.partialDescription = "部分数据读取时出现设备读写错误，请查看原始报告并检查连接。" }
            else if explicitlyUnsupported {
                s.partialDescription = "部分扩展日志不受当前接口或设备支持。"
            } else { s.partialDescription = "有读取命令未能完成，部分数据缺失，详细原因请查看原始报告。" }
        }
        if !hasHealth {
            if exit & 1 != 0 {
                s.explanation = "SMART 读取组件无法执行命令，请更新或重新安装本应用。详细原因可查看原始报告。"
            } else if diagnostic.contains("permission") || diagnostic.contains("operation not permitted") {
                s.explanation = "macOS 未允许读取此设备的 SMART。请检查设备访问权限；应用不会自动提权。"
            } else if diagnostic.contains("no such device") || diagnostic.contains("not found") {
                s.explanation = "设备已断开或设备号已变化，请重新扫描。"
            } else if diagnostic.contains("busy") || diagnostic.contains("userclient") || diagnostic.contains("open failed") {
                s.explanation = "设备的 SMART 读取通道暂时不可用，可能正在被其他程序占用。请稍后重新扫描。"
            } else if !diagnostic.contains("unsupported") && !diagnostic.contains("not supported") && !diagnostic.contains("not implemented") && !diagnostic.contains("unknown usb bridge") {
                s.explanation = "暂时未能读取此设备的 SMART，请重新扫描；详细原因可查看原始报告。"
            } else {
                s.explanation = "设备或 USB 转接芯片未透传 SMART。容量与分区信息仍可查看；可尝试直连接口或其他线缆。"
            }
            return s
        }
        s.health = passed == true ? .passed : .unavailable
        if passed == false || exit & 8 != 0 { s.health = .failed }
        let failingATA = ata.contains { ($0.string("when_failed") ?? "").lowercased() == "now" }
        if failingATA { s.health = .failed }
        let spareThreshold = j.dict("spare_available").number("threshold_percent") ?? nvme.number("available_spare_threshold")
        let critical = nvme.number("critical_warning") ?? 0
        let pastFailure = ata.contains { ($0.string("when_failed") ?? "").lowercased() == "past" }
        if s.health != .failed && (pastFailure || critical > 0 || (s.mediaErrors ?? 0) > 0 || (s.percentageUsed ?? 0) >= 100 ||
            (s.spare != nil && spareThreshold != nil && s.spare! < spareThreshold!) ||
            (s.temperature != nil && s.temperatureWarning != nil && s.temperature! >= s.temperatureWarning!)) {
            s.health = .attention
        }
        switch s.health {
        case .passed: s.explanation = "当前 SMART 健康检查通过。历史通电或断电计数不直接代表设备故障。"
        case .attention: s.explanation = "有健康指标或历史介质错误需要关注，请查看 SMART 明细。"
        case .failed: s.explanation = "设备报告了 SMART 异常，请优先保护重要数据并查看详细指标。"
        case .unavailable: s.explanation = "已读取部分指标，但设备未提供总体健康结论。"
        }
        if let partialDescription = s.partialDescription { s.explanation += " " + partialDescription }
        func add(_ id: String, _ name: String, _ value: String, _ note: String = "", _ flagged: Bool = false) {
            s.fields.append(SMARTField(id, name, value, note, flagged: flagged))
        }
        add("health", "总体健康检查", s.health.title, "来自设备固件的健康判断", s.health == .failed)
        add("temperature", "当前温度", s.temperature.map { DiskFormat.number($0) + " °C" } ?? "未提供", "读取时的温度，不是全程峰值")
        add("used", "寿命消耗", s.percentageUsed.map { DiskFormat.number($0) + "%" } ?? "未提供", "固件估算；0% 不表示绝对无磨损", (s.percentageUsed ?? 0) >= 100)
        add("spare", "可用备用空间", s.spare.map { DiskFormat.number($0) + "%" } ?? "未提供", "用于替换失效闪存的备用资源")
        add("hours", "累计通电", s.hours.map { DiskFormat.integer($0) + " 小时" } ?? "未提供", "按设备计数规则报告，通常为整小时")
        add("cycles", "通电次数", DiskFormat.integer(s.powerCycles), "设备生命周期内的累计计数")
        add("unsafe", "非正常关机", DiskFormat.integer(s.unsafeShutdowns), "未收到正常关机通知即断电；不能据此判断新旧")
        add("read", "累计读取", DiskFormat.bytes(s.bytesRead), "NVMe 标准单位或 ATA 标准逻辑扇区统计")
        add("written", "累计写入", DiskFormat.bytes(s.bytesWritten), "主机写入量，不等于 NAND 内部总写入量")
        add("media", "介质 / 数据完整性错误", DiskFormat.integer(s.mediaErrors), "累计不可恢复错误", (s.mediaErrors ?? 0) > 0)
        add("log", "错误日志条目", DiskFormat.integer(s.errorLogCount), "设备错误日志的累计条目", (s.errorLogCount ?? 0) > 0)
        if !nvme.isEmpty {
            add("critical", "严重警告位", String(format: "0x%02X", Int(critical)), "NVMe Critical Warning", critical > 0)
            add("tempwarning", "温度警告累计时间", nvme.number("warning_temp_time").map { DiskFormat.integer($0) + " 分钟" } ?? "未提供")
            add("tempcritical", "严重过热累计时间", nvme.number("critical_comp_time").map { DiskFormat.integer($0) + " 分钟" } ?? "未提供")
        }
        if !ata.isEmpty {
            add("reallocated", "重分配扇区", DiskFormat.integer(attribute(5)), "计数定义以厂商为准", (attribute(5) ?? 0) > 0)
            add("crc", "接口 CRC 错误", DiskFormat.integer(attribute(199)), "历史接口传输错误")
            add("timeout", "命令超时", DiskFormat.integer(attribute(188)), "历史计数；单次超时不直接判定为坏盘")
        }
        for row in ata {
            let id = Int(row.number("id") ?? 0)
            let name = row.string("name") ?? "Unknown"
            let raw = row.dict("raw").string("string") ?? "未提供"
            let note = "标准值 \(DiskFormat.integer(row.number("value"))) · 最差 \(DiskFormat.integer(row.number("worst"))) · 阈值 \(DiskFormat.integer(row.number("thresh")))"
            s.attributes.append(SMARTField(String(id), name, raw, note, flagged: !(row.string("when_failed") ?? "").isEmpty))
        }
        return s
    }
}
