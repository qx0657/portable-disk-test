import Foundation
import IOKit

public struct HardwareIdentity: Codable, Sendable {
    public var usbVendorID: Int?
    public var usbProductID: Int?
    public var usbVendorName: String?
    public var usbProductName: String?
    public var usbLinkBitsPerSecond: Double?
    public var serialNumber: String?
    public var pciVendorID: Int?
    public var pciDeviceID: Int?
    public var tunnelVendorID: Int?
    public var tunnelModelID: Int?
    public var tunnelUID: String?
    public var transportName: String?
    public var transportLinkBitsPerSecond: Double?
    public init(usbVendorID: Int? = nil, usbProductID: Int? = nil, usbVendorName: String? = nil,
                usbProductName: String? = nil, usbLinkBitsPerSecond: Double? = nil, serialNumber: String? = nil,
                pciVendorID: Int? = nil, pciDeviceID: Int? = nil, tunnelVendorID: Int? = nil, tunnelModelID: Int? = nil,
                tunnelUID: String? = nil, transportName: String? = nil, transportLinkBitsPerSecond: Double? = nil) {
        self.usbVendorID = usbVendorID; self.usbProductID = usbProductID
        self.usbVendorName = usbVendorName; self.usbProductName = usbProductName; self.usbLinkBitsPerSecond = usbLinkBitsPerSecond
        self.serialNumber = serialNumber; self.pciVendorID = pciVendorID; self.pciDeviceID = pciDeviceID
        self.tunnelVendorID = tunnelVendorID; self.tunnelModelID = tunnelModelID; self.tunnelUID = tunnelUID
        self.transportName = transportName; self.transportLinkBitsPerSecond = transportLinkBitsPerSecond
    }
    public var usbID: String? {
        guard let vendor = usbVendorID, let product = usbProductID else { return nil }
        return String(format: "%04X:%04X", vendor, product)
    }
    public static func read(deviceID: String) -> HardwareIdentity? {
        guard DiskService.validDeviceID(deviceID), let matching = IOBSDNameMatching(kIOMainPortDefault, 0, deviceID) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        // 从这一块盘的 IOMedia 向父设备查找，不能按设备名称全局匹配，否则同型号多盘会串线。
        func property(_ name: String) -> Any? {
            IORegistryEntrySearchCFProperty(service, kIOServicePlane, name as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively))
        }
        func identifier(_ value: Any?) -> Int? {
            if let n = value as? NSNumber { return n.intValue }
            guard let data = value as? Data, data.count >= 4 else { return nil }
            return data.prefix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        }
        var result = HardwareIdentity(usbVendorID: (property("idVendor") as? NSNumber)?.intValue,
            usbProductID: (property("idProduct") as? NSNumber)?.intValue,
            usbVendorName: property("USB Vendor Name") as? String,
            usbProductName: property("USB Product Name") as? String,
            usbLinkBitsPerSecond: (property("UsbLinkSpeed") as? NSNumber)?.doubleValue,
            serialNumber: property("INQUIRY Unit Serial Number") as? String ?? property("USB Serial Number") as? String ?? property("Serial Number") as? String,
            pciVendorID: identifier(property("vendor-id")), pciDeviceID: identifier(property("device-id")))
        // Follow this disk's PCI tunnel path, never a name search across all USB4 devices.
        if result.usbVendorID == nil, let path = property("Thunderbolt Path") as? String {
            var current = IORegistryEntryFromPath(kIOMainPortDefault, path)
            for _ in 0..<12 {
                guard current != 0 else { break }
                if IOObjectConformsTo(current, "IOThunderboltSwitchUSB4") != 0 {
                    func own(_ name: String) -> Any? { IORegistryEntryCreateCFProperty(current, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
                    result.tunnelVendorID = (own("Device Vendor ID") as? NSNumber)?.intValue
                    result.tunnelModelID = (own("Device Model ID") as? NSNumber)?.intValue
                    if let uid = own("UID") as? NSNumber { result.tunnelUID = String(format: "%016llX", uid.uint64Value) }
                    result.transportName = "USB4"
                    IOObjectRelease(current); current = 0; break
                }
                var parent: io_registry_entry_t = 0
                let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
                IOObjectRelease(current)
                current = status == KERN_SUCCESS ? parent : 0
            }
            if current != 0 { IOObjectRelease(current) }
        }
        guard result.usbVendorID != nil || result.pciVendorID != nil || result.serialNumber != nil else { return nil }
        return result
    }
}

public enum DriveBrand: String, Sendable {
    case sandisk, samsung, westernDigital, seagate, kingston, crucial, kioxia, toshiba, lexar, adata, unknown
    public var title: String {
        switch self {
        case .sandisk: return "闪迪 SanDisk"
        case .samsung: return "三星 Samsung"
        case .westernDigital: return "西部数据 WD"
        case .seagate: return "希捷 Seagate"
        case .kingston: return "金士顿 Kingston"
        case .crucial: return "英睿达 Crucial"
        case .kioxia: return "铠侠 KIOXIA"
        case .toshiba: return "东芝 Toshiba"
        case .lexar: return "雷克沙 Lexar"
        case .adata: return "威刚 ADATA"
        case .unknown: return "未识别品牌"
        }
    }
}

public struct DeviceProfile: Sendable {
    public var brand: DriveBrand
    public var series: String?
    public var directlyReported = false
    public var reportedPartNumber: String?
    public var basis: String?
    public var seriesSource: DeviceIdentitySource?
    public var sourceURL: URL?
    public var confirmedLabel: DeviceLabel?
    public var partNumber: String? { reportedPartNumber ?? confirmedLabel?.partNumber }
    public var partNumberSource: DeviceIdentitySource? {
        reportedPartNumber != nil ? .device : confirmedLabel.map { $0.source == .photo ? .label : .manual }
    }
    public var seriesLabel: String? {
        series.map { "\($0) · \(seriesSource?.title ?? "设备报告")" }
    }
}

public enum DeviceCatalog {
    public static func profile(for disk: DiskDevice, label: DeviceLabel? = nil) -> DeviceProfile {
        let name = disk.model.lowercased()
        let vendor = disk.hardware?.usbVendorName?.lowercased() ?? ""
        var brand: DriveBrand = .unknown
        if name.contains("sandisk") || name.contains("闪迪") || name.contains("sdssde") || vendor.contains("sandisk") || disk.hardware?.usbVendorID == 0x0781 || disk.hardware?.tunnelVendorID == 0x0781 { brand = .sandisk }
        else if name.contains("samsung") || vendor.contains("samsung") { brand = .samsung }
        else if name.hasPrefix("wdc ") || name.hasPrefix("wd_black") || name.contains("western digital") || vendor.contains("western digital") { brand = .westernDigital }
        else if name.contains("seagate") || vendor.contains("seagate") { brand = .seagate }
        else if name.contains("kingston") || vendor.contains("kingston") { brand = .kingston }
        else if name.contains("crucial") || vendor.contains("crucial") { brand = .crucial }
        else if name.contains("kioxia") || vendor.contains("kioxia") { brand = .kioxia }
        else if name.contains("toshiba") || vendor.contains("toshiba") { brand = .toshiba }
        else if name.contains("lexar") || vendor.contains("lexar") { brand = .lexar }
        else if name.contains("adata") || vendor.contains("adata") { brand = .adata }
        var result = DeviceProfile(brand: brand, confirmedLabel: label)
        guard brand == .sandisk else { return result }
        let model = disk.model as NSString
        let regex = try! NSRegularExpression(pattern: #"\bSDSSDE([0-9][A-Z0-9]{1,3})((?:-[A-Z0-9]+){0,3})\b"#, options: .caseInsensitive)
        if let match = regex.firstMatch(in: disk.model, range: NSRange(location: 0, length: model.length)) {
            result.series = "E" + model.substring(with: match.range(at: 1)).uppercased()
            let part = model.substring(with: match.range(at: 0)).uppercased()
            result.reportedPartNumber = PartNumber.sanDiskRetail(part)
            result.directlyReported = true
            result.seriesSource = .device
            result.basis = "设备型号字符串直接提供 \(part)。完整料号只在设备实际提供时显示，不根据容量补全。"
        } else if ManufacturerCatalog.matchesE82(disk.hardware) {
            result.series = "E82"; result.seriesSource = .manufacturer
            result.sourceURL = ManufacturerCatalog.e82ProductURL
            result.basis = "硬件标识对应闪迪官方 App 3.4.2 产品目录中的 Extreme PRO with USB4，系列代码依据官方产品资料。匹配只确认产品系列，不补全容量或区域料号。"
        } else if let label, let series = PartNumber.sanDiskSeries(label.partNumber) {
            result.series = series; result.seriesSource = label.source == .photo ? .label : .manual
            result.basis = "产品系列来自已确认的补充料号，保存在这台 Mac 上；设备报告的 Model 未被修改。"
        }
        return result
    }
}

public enum BenchmarkPurpose: String, CaseIterable, Identifiable, Sendable {
    case quick = "快速检查", comparison = "日常对比", workingSet = "较大工作集"
    public var id: String { rawValue }
}

public struct BenchmarkAdvice: Sendable {
    public var iterations: Int
    public var sizeMiB: Int
    public var reason: String
    public var scope: String
    public var blockedReason: String?
    public var sizeLabel: String { sizeMiB >= 1024 ? "\(sizeMiB / 1024) GiB" : "\(sizeMiB) MiB" }
    public var parameterLabel: String { "\(iterations) 次   ·   \(sizeLabel)   ·   MB/s" }
    public static func recommend(for disk: DiskDevice, volume: DiskVolume?, purpose: BenchmarkPurpose) -> BenchmarkAdvice {
        let nvme = disk.snapshot.protocolName?.caseInsensitiveCompare("NVMe") == .orderedSame
        let ata = disk.snapshot.protocolName?.caseInsensitiveCompare("ATA") == .orderedSame
        let rotational = disk.solidState == false
        let observedUSB = disk.bus == "USB" ? disk.hardware?.usbLinkBitsPerSecond : nil
        let slowUSB = observedUSB.map { $0 < 1_000_000_000 } ?? false
        let fastNVMe = nvme && (disk.bus == "PCI-Express" || (observedUSB ?? 0) >= 20_000_000_000)
        let normalSize = slowUSB ? 512 : fastNVMe ? 4096 : (observedUSB ?? .infinity) <= 5_000_000_000 ? 1024 : nvme ? 2048 : 1024
        let largeSize = slowUSB ? 1024 : rotational ? 4096 : fastNVMe ? 16384 : 8192
        let size = purpose == .quick ? (slowUSB || rotational ? 256 : 1024) : purpose == .comparison ? normalSize : largeSize
        let iterations = purpose == .comparison ? 3 : 1
        let category = rotational ? "机械硬盘" : fastNVMe ? "通过高速总线连接的 NVMe 设备" : nvme ? "NVMe 设备" : ata ? "ATA / SATA 设备" : "当前外接设备"
        var reason: String
        switch purpose {
        case .quick: reason = "针对\(category)，用较小文件跑一轮，快速检查读写是否工作；这组参数优先节省时间。"
        case .comparison: reason = "针对\(category)选择工作文件大小。重复 3 次用于减少偶然波动，适合同条件下比较前后成绩。"
        case .workingSet: reason = "针对\(category)扩大读写文件范围，先跑 1 次；需要观察稳定性时，再在相同条件下复测。"
        }
        var advice = BenchmarkAdvice(iterations: iterations, sizeMiB: size, reason: reason,
            scope: purpose == .workingSet ? "较大工作集仍可能落在 SSD 缓存内，不能据此证明缓存耗尽后的持续写入速度，也不是全盘容量校验。" : "用于短时性能观察；参数由本应用按设备与用途建议，不是厂商认证标准。", blockedReason: nil)
        guard let volume else { advice.blockedReason = "请先挂载需要测速的卷。"; return advice }
        guard volume.writable else { advice.blockedReason = "此卷为只读，无法进行写入测速。"; return advice }
        if disk.snapshot.health == .failed { advice.blockedReason = "设备已报告 SMART 故障，请先保护重要数据，暂不建议写入测速。"; return advice }
        if let temp = disk.snapshot.temperature, let warning = disk.snapshot.temperatureWarning, temp >= warning {
            advice.blockedReason = "设备已达到固件报告的温度警告阈值，请降温后再测速。"; return advice
        }
        if let free = volume.free {
            let reserve = max(256 * 1_048_576.0, min(1_073_741_824.0, free * 0.1))
            let budgetMiB = max(0, (free - reserve) / 1_048_576)
            if let supported = [256, 512, 1024, 2048, 4096, 8192, 16384].last(where: { $0 <= size && Double($0) <= budgetMiB }) {
                advice.sizeMiB = supported
                if supported < size { advice.reason += " 已根据当前可用空间下调文件大小，并预留额外空间。" }
            } else { advice.blockedReason = "可用空间不足以容纳测速文件及预留空间，请先腾出空间。" }
        } else {
            advice.sizeMiB = min(advice.sizeMiB, 1024)
            advice.reason += " 未读取到可用空间，采用保守文件大小；请在测速工具中确认剩余空间。"
        }
        return advice
    }
}
