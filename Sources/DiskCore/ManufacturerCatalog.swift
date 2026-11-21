import Foundation

public enum DeviceIdentitySource: String, Sendable {
    case device, manufacturer, label, manual
    public var title: String {
        switch self {
        case .device: return "设备报告"
        case .manufacturer: return "官方资料匹配"
        case .label: return "标签确认"
        case .manual: return "手动确认"
        }
    }
}

public enum ManufacturerCatalog {
    // Facts verified from SANDISK App 3.4.2 (2717) products.json on an Apple Silicon Mac mini,
    // 2026-11-20. Full origin and digest: Resources/ManufacturerCatalog.provenance.json.
    // 0781:558C (the user's E60) is absent: intentionally no rule for it.
    public static let e82ProductURL = URL(string: "https://www.sandisk.com/products/ssd/external-ssd/sandisk-extreme-pro-usb-4-portable-ssd")!
    public static func matchesE82(_ h: HardwareIdentity?) -> Bool {
        guard let h else { return false }
        if h.usbVendorID == 0x0781 && h.usbProductID == 0x55c8 { return true }
        // In PCIe tunnel mode require both the NVMe ID and its own USB4 enclosure ID.
        return [0x0781, 0x15b7].contains(h.pciVendorID ?? -1) && h.pciDeviceID == 0x5030
            && h.tunnelVendorID == 0x0781 && h.tunnelModelID == 0x55c8
    }
}

public enum ThunderboltLinkIndex {
    public static func normalizeUID(_ uid: String) -> String? {
        let text = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        guard !digits.isEmpty, digits.count <= 16, let n = UInt64(digits, radix: 16) else { return nil }
        return String(format: "%016llX", n)
    }
    public static func parse(_ data: Data) throws -> [String: Double] {
        let root = try JSONSerialization.jsonObject(with: data)
        var observations: [String: [Double]] = [:]
        func walk(_ node: Any) {
            if let a = node as? [Any] { a.forEach(walk); return }
            guard let o = node as? [String: Any] else { return }
            let upstream = o["receptacle_upstream_ambiguous_tag"] as? [String: Any] ?? [:]
            if let rawUID = o["switch_uid_key"] as? String, let uid = normalizeUID(rawUID),
               o["mode_key"] as? String == "usb_four",
               let speed = upstream["current_speed_key"] as? String,
               let range = speed.range(of: #"[0-9]+(?:\.[0-9]+)?(?=\s*Gb/s)"#, options: .regularExpression),
               let gbps = Double(speed[range]), gbps > 0, gbps <= 120 {
                observations[uid, default: []].append(gbps * 1_000_000_000)
            }
            o.values.forEach(walk)
        }
        walk(root)
        // Duplicate UIDs do not establish a unique device-to-link relationship.
        return observations.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
    public static func read() throws -> [String: Double] {
        let r = try CommandRunner.run("/usr/sbin/system_profiler", ["-json", "SPThunderboltDataType"], timeout: 12)
        guard r.status == 0 else { return [:] }
        return try parse(r.data)
    }
}
