import Foundation

public enum HealthState: String, Codable, Sendable {
    case passed, attention, failed, unavailable
    public var title: String {
        switch self {
        case .passed: return "SMART 检查通过"
        case .attention: return "有指标需要关注"
        case .failed: return "SMART 检测到异常"
        case .unavailable: return "SMART 暂不可用"
        }
    }
}

public struct SMARTField: Identifiable, Codable, Sendable {
    public var id: String
    public var name: String
    public var value: String
    public var note: String
    public var flagged: Bool
    public init(_ id: String, _ name: String, _ value: String, _ note: String = "", flagged: Bool = false) {
        self.id = id; self.name = name; self.value = value; self.note = note; self.flagged = flagged
    }
}

public struct SMARTSnapshot: Codable, Sendable {
    public var date = Date()
    public var model: String?
    public var serial: String?
    public var firmware: String?
    public var protocolName: String?
    public var health: HealthState = .unavailable
    public var partial = false
    public var partialDescription: String?
    public var explanation = "设备或当前连接方式未提供 SMART 数据。"
    public var temperature: Double?
    public var temperatureWarning: Double?
    public var percentageUsed: Double?
    public var spare: Double?
    public var hours: Double?
    public var powerCycles: Double?
    public var unsafeShutdowns: Double?
    public var bytesRead: Double?
    public var bytesWritten: Double?
    public var mediaErrors: Double?
    public var errorLogCount: Double?
    public var fields: [SMARTField] = []
    public var attributes: [SMARTField] = []
    public var rawJSON = ""
    public var rawText = ""
    public init() {}
}

public struct DiskVolume: Identifiable, Codable, Sendable {
    public var id: String
    public var uuid: String?
    public var name: String
    public var mountPoint: String?
    public var filesystem: String
    public var capacity: Double
    public var free: Double?
    public var writable: Bool
    public var used: Double? { free.map { max(0, capacity - $0) } }
    public init(id: String, uuid: String?, name: String, mountPoint: String?, filesystem: String,
                capacity: Double, free: Double?, writable: Bool) {
        self.id = id; self.uuid = uuid; self.name = name; self.mountPoint = mountPoint
        self.filesystem = filesystem; self.capacity = capacity; self.free = free; self.writable = writable
    }
}

public struct DiskDevice: Identifiable, Codable, Sendable {
    public var id: String
    public var mediaName: String
    public var capacity: Double
    public var bus: String
    public var solidState: Bool?
    public var partitionMap: String
    public var volumes: [DiskVolume]
    public var snapshot: SMARTSnapshot
    public var hardware: HardwareIdentity?
    public var identityAmbiguous = false
    public var persistentIdentity: String? {
        guard !identityAmbiguous else { return nil }
        if let serial = snapshot.serial?.trimmingCharacters(in: .whitespacesAndNewlines),
           serial.count >= 3, !["unknown", "none", "n/a", "not specified"].contains(serial.lowercased()),
           serial.contains(where: { $0 != "0" && $0 != " " && $0 != "-" }) {
            return "serial:\(serial)"
        }
        let uuids = volumes.compactMap(\.uuid).filter { !$0.isEmpty }.sorted()
        guard !uuids.isEmpty, Set(uuids).count == uuids.count else { return nil }
        return "volume:\(uuids.joined(separator: "|"))"
    }
    public var labelIdentity: String? {
        guard !identityAmbiguous else { return nil }
        // Physical serials only: volume UUIDs can be cloned or replaced by reformatting.
        let serial = [hardware?.serialNumber, snapshot.serial].compactMap { $0 }.first { Self.validSerial($0) }
        return serial.map { "hardware:" + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    public static func validSerial(_ value: String) -> Bool {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count >= 3 && s.count <= 256 && !["unknown", "none", "n/a", "not specified", "null"].contains(s.lowercased())
            && !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && s.contains(where: { $0 != "0" && $0 != " " && $0 != "-" })
    }
    // 没有可靠身份时只用于当前界面，绝不作为持久化历史记录的键。
    public var identity: String { persistentIdentity ?? "session:\(id)" }
    public var displayName: String { volumes.first(where: { $0.mountPoint != nil })?.name ?? mediaName }
    public var model: String { snapshot.model ?? mediaName }
    public var profile: DeviceProfile { DeviceCatalog.profile(for: self) }
    public var isSanDisk: Bool { profile.brand == .sandisk }
    public var connection: String {
        var observedBus = hardware?.transportName ?? (bus == "PCI-Express" ? "PCIe" : bus)
        if let bps = hardware?.transportLinkBitsPerSecond, bps > 0 {
            observedBus += " \(DiskFormat.number(bps / 1_000_000_000)) Gb/s"
        }
        if bus == "USB", let bps = hardware?.usbLinkBitsPerSecond, bps > 0 {
            observedBus += bps >= 1_000_000_000 ? " \(DiskFormat.number(bps / 1_000_000_000)) Gb/s" : " \(DiskFormat.number(bps / 1_000_000)) Mb/s"
        }
        return [observedBus, snapshot.protocolName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    public init(id: String, mediaName: String, capacity: Double, bus: String, solidState: Bool?,
                partitionMap: String, volumes: [DiskVolume], snapshot: SMARTSnapshot) {
        self.id = id; self.mediaName = mediaName; self.capacity = capacity; self.bus = bus
        self.solidState = solidState; self.partitionMap = partitionMap; self.volumes = volumes; self.snapshot = snapshot
    }
}

public enum DiskFormat {
    public static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "未提供" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var n = value; var index = 0
        while n >= 1000 && index < units.count - 1 { n /= 1000; index += 1 }
        let format = index == 0 ? "%.0f %@" : (n >= 100 ? "%.1f %@" : "%.2f %@")
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), n, units[index])
    }
    public static func integer(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
    public static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension Dictionary where Key == String, Value == Any {
    func dict(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func array(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func string(_ key: String) -> String? {
        guard let value = self[key] as? String, !value.isEmpty else { return nil }
        return value
    }
    func number(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }
}
