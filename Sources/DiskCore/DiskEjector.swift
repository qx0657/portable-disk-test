import Foundation
import DiskArbitration
import IOKit

public enum DiskEjectError: LocalizedError, Sendable, Equatable {
    case changed, unavailable, invalidTarget, busy, denied, system(Int32)
    public var errorDescription: String? {
        switch self {
        case .changed: return "设备已断开或重新连接。请重新扫描，核对目标硬盘后再推出。"
        case .unavailable: return "无法连接系统推出服务。请在访达中尝试推出。"
        case .invalidTarget: return "无法确认目标为外接物理硬盘，未执行推出。请重新扫描。"
        case .busy: return "硬盘正在使用。请结束复制、备份或测速，关闭使用盘中文件的软件，再重试。"
        case .denied: return "系统未允许推出这块硬盘。请在访达中尝试推出。"
        case .system(let code): return "系统未完成推出（错误码 \(code)）。请在访达中重试；仍失败时可正常关闭 Mac 后再拔线。"
        }
    }
    public static func from(status: Int32) -> Self {
        switch status {
        case Int32(truncatingIfNeeded: kDAReturnBusy), Int32(truncatingIfNeeded: kDAReturnExclusiveAccess): return .busy
        case Int32(truncatingIfNeeded: kDAReturnNotPermitted), Int32(truncatingIfNeeded: kDAReturnNotPrivileged): return .denied
        case Int32(truncatingIfNeeded: kDAReturnNotFound): return .changed
        default: return .system(status)
        }
    }
}

public struct DiskEjectTarget: Sendable {
    public let deviceID: String
    public let registryID: UInt64
    public init(deviceID: String, registryID: UInt64) { self.deviceID = deviceID; self.registryID = registryID }
    public func validate(deviceID currentID: String, registryID currentRegistryID: UInt64,
                         internalDisk: Bool?, wholeDisk: Bool?, physical: Bool) throws {
        guard deviceID.range(of: "^disk[0-9]+$", options: .regularExpression) != nil,
              registryID != 0, internalDisk == false, wholeDisk == true, physical else { throw DiskEjectError.invalidTarget }
        guard currentID == deviceID, currentRegistryID == registryID else { throw DiskEjectError.changed }
    }
}

public protocol DiskEjectionDriver: Sendable {
    func unmountWholeDisk() async throws
    func ejectDisk() async throws
}

/// A success message is permission for one connection only, never a persistent health fact.
public struct DiskEjectionReceipt: Sendable {
    public let targetRegistryID: UInt64
    private let otherConnectedRegistryIDs: Set<UInt64>
    public private(set) var isValid = true
    public init(targetRegistryID: UInt64, otherConnectedRegistryIDs: Set<UInt64>) {
        self.targetRegistryID = targetRegistryID
        self.otherConnectedRegistryIDs = otherConnectedRegistryIDs.subtracting([targetRegistryID])
    }
    public mutating func reconcile(connectedRegistryIDs: Set<UInt64>?) {
        // Unknown state (a mount notification or discovery failure) revokes the old permission.
        guard let connectedRegistryIDs else { isValid = false; return }
        isValid = isValid && !connectedRegistryIDs.contains(targetRegistryID)
            && connectedRegistryIDs.isSubset(of: otherConnectedRegistryIDs)
    }
}

public enum DiskEjector {
    public static func registryID(for deviceID: String) -> UInt64? {
        guard DiskService.validDeviceID(deviceID), let match = IOBSDNameMatching(kIOMainPortDefault, 0, deviceID) else { return nil }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard media != 0 else { return nil }
        defer { IOObjectRelease(media) }
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(media, &id) == KERN_SUCCESS, id != 0 else { return nil }
        return id
    }
    public static func eject(_ disk: DiskDevice) async throws {
        let driver = try await prepare(disk)
        try await perform(using: driver)
    }
    /// Read-only preflight for diagnostics. Does not submit an unmount or eject request.
    public static func validate(_ disk: DiskDevice) async throws { _ = try await prepare(disk) }
    private static func prepare(_ disk: DiskDevice) async throws -> NativeEjectionDriver {
        guard let registryID = disk.mediaRegistryID else { throw DiskEjectError.invalidTarget }
        return try await Task.detached(priority: .utility) {
            try NativeEjectionDriver(target: DiskEjectTarget(deviceID: disk.id, registryID: registryID))
        }.value
    }
    public static func perform(using driver: any DiskEjectionDriver) async throws {
        // No force option: a veto or busy file stops the sequence before eject.
        try await driver.unmountWholeDisk()
        try await driver.ejectDisk()
    }
}

private final class NativeEjectionDriver: DiskEjectionDriver, @unchecked Sendable {
    private let session: DASession
    private let disk: DADisk
    private let queue = DispatchQueue(label: "com.glow.portabledisktest.eject")
    init(target: DiskEjectTarget) throws {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { throw DiskEjectError.unavailable }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(target.registryID))
        guard media != 0 else { throw DiskEjectError.changed }
        defer { IOObjectRelease(media) }
        guard let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, media),
              let name = DADiskGetBSDName(disk), let description = DADiskCopyDescription(disk) as? [String: Any] else {
            throw DiskEjectError.changed
        }
        var registryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(media, &registryID) == KERN_SUCCESS else { throw DiskEjectError.changed }
        // diskutil's physical check supplements Disk Arbitration's whole/external flags.
        let output = try CommandRunner.run("/usr/sbin/diskutil", ["info", "-plist", target.deviceID], timeout: 12)
        let info = (try? PropertyListSerialization.propertyList(from: output.data, format: nil)) as? [String: Any]
        try target.validate(deviceID: String(cString: name), registryID: registryID,
            internalDisk: description[kDADiskDescriptionDeviceInternalKey as String] as? Bool,
            wholeDisk: description[kDADiskDescriptionMediaWholeKey as String] as? Bool,
            physical: output.status == 0 && info?["VirtualOrPhysical"] as? String == "Physical")
        // Recheck after the read-only subprocess; the DADisk object stays bound to this IOMedia.
        guard DiskEjector.registryID(for: target.deviceID) == target.registryID else { throw DiskEjectError.changed }
        self.session = session; self.disk = disk
        DASessionSetDispatchQueue(session, queue)
    }
    deinit { DASessionSetDispatchQueue(session, nil) }
    func unmountWholeDisk() async throws { try await request(unmount: true) }
    func ejectDisk() async throws { try await request(unmount: false) }
    private func request(unmount: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let context = Unmanaged.passRetained(EjectionCallback(owner: self, unmount: unmount, continuation: continuation)).toOpaque()
                if unmount {
                    DADiskUnmount(self.disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), ejectionCallback, context)
                } else {
                    DADiskEject(self.disk, DADiskEjectOptions(kDADiskEjectOptionDefault), ejectionCallback, context)
                }
            }
        }
    }
}

private final class EjectionCallback {
    // Keep the session and disk alive until the native completion arrives, including slow operations.
    let owner: NativeEjectionDriver
    let unmount: Bool
    let continuation: CheckedContinuation<Void, Error>
    init(owner: NativeEjectionDriver, unmount: Bool, continuation: CheckedContinuation<Void, Error>) {
        self.owner = owner; self.unmount = unmount; self.continuation = continuation
    }
}
private func ejectionCallback(_ disk: DADisk, _ dissenter: DADissenter?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let callback = Unmanaged<EjectionCallback>.fromOpaque(context).takeRetainedValue()
    if let dissenter, !(callback.unmount && DADissenterGetStatus(dissenter) == Int32(truncatingIfNeeded: kDAReturnNotMounted)) {
        callback.continuation.resume(throwing: DiskEjectError.from(status: DADissenterGetStatus(dissenter)))
    }
    else { callback.continuation.resume() }
}
