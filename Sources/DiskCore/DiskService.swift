import Foundation
import Darwin

public struct CommandOutput: Sendable {
    public var data: Data
    public var error: String
    public var status: Int32
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func set(_ data: Data) { lock.lock(); storage = data; lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return storage }
}

public enum CommandRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: Double = 15) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let errorBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.set(errors.fileHandleForReading.readDataToEndOfFile()); group.leave()
        }
        let timeoutItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeoutItem.cancel(); group.wait()
        let stderr = String(data: errorBox.value, encoding: .utf8) ?? ""
        return CommandOutput(data: data, error: stderr, status: process.terminationStatus)
    }
}

public enum DiskServiceError: LocalizedError {
    case discovery(String)
    public var errorDescription: String? {
        switch self { case .discovery(let message): return message }
    }
}

public struct DiskService: Sendable {
    public let smartctlPath: String?
    public init(smartctlPath: String?) { self.smartctlPath = smartctlPath }
    private func plist(_ args: [String]) throws -> [String: Any] {
        let r = try CommandRunner.run("/usr/sbin/diskutil", args, timeout: 12)
        guard r.status == 0, let dict = (try? PropertyListSerialization.propertyList(from: r.data, format: nil)) as? [String: Any] else {
            throw DiskServiceError.discovery(r.error.isEmpty ? "磁盘信息暂时无法读取，请重新扫描。" : r.error)
        }
        return dict
    }
    public static func validDeviceID(_ id: String) -> Bool {
        id.range(of: "^disk[0-9]+(?:s[0-9]+)*$", options: .regularExpression) != nil
    }
    public static func identifiers(in record: [String: Any]) -> [String] {
        var result: [String] = []
        for key in ["Partitions", "APFSVolumes", "Volumes", "AllDisksAndPartitions"] {
            for child in record.array(key) {
                if let id = child.string("DeviceIdentifier"), validDeviceID(id) { result.append(id) }
                result += identifiers(in: child)
            }
        }
        return Array(Set(result)).sorted()
    }
    public func scan(cached: [DiskDevice] = [], force: Bool = false) throws -> [DiskDevice] {
        let list = try plist(["list", "-plist", "external", "physical"])
        var found: [DiskDevice] = []
        for disk in list.array("AllDisksAndPartitions") {
            guard let id = disk.string("DeviceIdentifier"), Self.validDeviceID(id),
                  let info = try? plist(["info", "-plist", id]),
                  info["Internal"] as? Bool == false,
                  info["WholeDisk"] as? Bool == true,
                  info.string("VirtualOrPhysical") != "Virtual" else { continue }
            let media = info.string("MediaName") ?? "外接磁盘"
            var volumeInfos: [[String: Any]] = []
            var candidates = Self.identifiers(in: disk)
            if info.string("MountPoint") != nil { candidates.append(id) }
            var visited = Set<String>()
            while let next = candidates.first {
                candidates.removeFirst()
                guard visited.insert(next).inserted, let v = try? plist(["info", "-plist", next]) else { continue }
                // APFS 的卷在合成容器内，不把合成盘当成第二台物理设备。
                if let container = v.string("APFSContainerReference"), Self.validDeviceID(container),
                   !visited.contains(container), let tree = try? plist(["list", "-plist", container]) {
                    visited.insert(container)
                    candidates += Self.identifiers(in: tree).filter { !visited.contains($0) }
                }
                if v.string("Content") == "EFI" || v.string("Content") == "Apple_APFS" { continue }
                if v.string("VolumeName") != nil || v.string("MountPoint") != nil || v.string("FilesystemType") != nil { volumeInfos.append(v) }
            }
            let volumes = volumeInfos.map { v in
                DiskVolume(id: v.string("DeviceIdentifier") ?? "", uuid: v.string("VolumeUUID"),
                           name: v.string("VolumeName") ?? "未命名卷", mountPoint: v.string("MountPoint"),
                           filesystem: v.string("FilesystemName") ?? v.string("FilesystemType") ?? "未识别",
                           capacity: v.number("VolumeSize") ?? v.number("TotalSize") ?? v.number("Size") ?? 0,
                           free: v.number("FreeSpace") ?? v.number("APFSContainerFree"),
                           writable: v["WritableVolume"] as? Bool ?? v["Writable"] as? Bool ?? false)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let capacity = info.number("Size") ?? disk.number("Size") ?? 0
            let old = cached.first { $0.id == id && $0.mediaName == media && $0.capacity == capacity &&
                $0.volumes.compactMap(\.uuid).sorted() == volumes.compactMap(\.uuid).sorted() }
            let snapshot: SMARTSnapshot
            if !force, let old, Date().timeIntervalSince(old.snapshot.date) < 30 {
                snapshot = old.snapshot
            } else if let path = smartctlPath {
                do {
                    var result = try CommandRunner.run(path, ["--json=o", "-x", "/dev/\(id)"], timeout: 15)
                    let diagnostic = (String(data: result.data, encoding: .utf8) ?? "") + result.error
                    if result.status & 2 != 0,
                       !diagnostic.localizedCaseInsensitiveContains("permission"),
                       !diagnostic.localizedCaseInsensitiveContains("operation not permitted"),
                       ["busy", "userclient", "open failed", "failed to open"].contains(where: { diagnostic.localizedCaseInsensitiveContains($0) }) {
                        // USB SMART 客户端可能被另一工具短暂占用，只重试一次，不把争用当成永久不支持。
                        Thread.sleep(forTimeInterval: 0.2)
                        result = try CommandRunner.run(path, ["--json=o", "-x", "/dev/\(id)"], timeout: 15)
                    }
                    snapshot = SMARTParser.parse(result.data, status: result.status, stderr: result.error)
                } catch {
                    var failure = SMARTSnapshot(); failure.explanation = "SMART 读取失败：\(error.localizedDescription)"; snapshot = failure
                }
            } else {
                var missing = SMARTSnapshot()
                missing.explanation = "未找到 SMART 读取组件。请重新安装完整应用，或安装 smartmontools 后重新扫描。"
                snapshot = missing
            }
            var device = DiskDevice(id: id, mediaName: media, capacity: capacity,
                                    bus: info.string("BusProtocol") ?? "未提供", solidState: info["SolidState"] as? Bool,
                                    partitionMap: info.string("Content") ?? disk.string("Content") ?? "未提供",
                                    volumes: volumes, snapshot: snapshot)
            device.hardware = HardwareIdentity.read(deviceID: id)
            found.append(device)
        }
        let needsLinkRead = found.contains { disk in
            guard let uid = disk.hardware?.tunnelUID else { return false }
            return force || !cached.contains { $0.hardware?.tunnelUID == uid && $0.snapshot.date == disk.snapshot.date }
        }
        let links = needsLinkRead ? (try? ThunderboltLinkIndex.read()) ?? [:] : [:]
        for i in found.indices {
            guard let uid = found[i].hardware?.tunnelUID else { continue }
            if needsLinkRead { found[i].hardware?.transportLinkBitsPerSecond = links[uid] }
            else { found[i].hardware?.transportLinkBitsPerSecond = cached.first { $0.hardware?.tunnelUID == uid }?.hardware?.transportLinkBitsPerSecond }
        }
        return Self.enforceUniqueIdentities(found).sorted {
            if $0.isSanDisk != $1.isSanDisk { return $0.isSanDisk }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
    public static func enforceUniqueIdentities(_ devices: [DiskDevice]) -> [DiskDevice] {
        let counts = Dictionary(grouping: devices.compactMap(\.persistentIdentity), by: { $0 }).mapValues(\.count)
        let labelCounts = Dictionary(grouping: devices.compactMap(\.labelIdentity), by: { $0 }).mapValues(\.count)
        return devices.map { disk in
            var copy = disk
            if let key = copy.persistentIdentity, (counts[key] ?? 0) > 1 { copy.identityAmbiguous = true }
            if let key = disk.labelIdentity, (labelCounts[key] ?? 0) > 1 { copy.identityAmbiguous = true }
            return copy
        }
    }
    public static func locateSMART(executableDirectory: URL? = nil) -> String? {
        var candidates: [String] = []
        if let dir = executableDirectory { candidates.append(dir.appendingPathComponent("smartctl").path) }
        candidates += ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/usr/local/sbin/smartctl", "/opt/local/sbin/smartctl"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
