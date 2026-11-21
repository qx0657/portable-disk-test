import Foundation
import DiskCore
import CoreGraphics
import CoreText
import ImageIO

struct DiskCoreTests {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    func testRealNVMeFixtureAndStandardUnits() throws {
        let result = SMARTParser.parse(try fixture("e82"))
        checkEqual(result.health, .passed)
        checkEqual(result.serial, "E82-FIXTURE")
        checkEqual(result.percentageUsed, 0)
        checkEqual(result.unsafeShutdowns, 6)
        checkEqual(result.powerCycles, 10)
        checkNotNil(result.temperature)
        checkGreaterThan(result.bytesWritten ?? 0, 75_000_000_000)
        checkFalse(result.rawText.isEmpty)
        checkFalse(result.rawText.hasPrefix("{"))
        checkEqual(result.mediaErrors, 0)
    }
    func testRealATAFixturePartialLogsAreNotHealthFailure() throws {
        let data = try fixture("e60")
        let result = SMARTParser.parse(data, status: 4)
        checkEqual(result.health, .passed)
        checkTrue(result.partial)
        checkEqual(result.serial, "E60-FIXTURE")
        checkEqual(result.percentageUsed, 0)
        checkTrue(result.attributes.contains { $0.id == "241" && $0.value == "2429" })
        checkLessThan(result.temperature ?? 1000, 100)
        checkGreaterThan(result.bytesWritten ?? 0, 2_600_000_000_000)
        checkLessThan(result.bytesWritten ?? 0, 2_700_000_000_000)
        checkTrue(result.explanation.contains("部分扩展日志"))
        checkNil(result.unsafeShutdowns) // 不猜测厂商未知属性 174 的含义。
    }
    func testMissingMetricsDoNotBecomeZeroOrHealthy() throws {
        let result = SMARTParser.parse(try json(["smartctl": ["exit_status": 2], "smart_support": ["available": false]]))
        checkEqual(result.health, .unavailable)
        checkNil(result.temperature)
        checkNil(result.percentageUsed)
        checkNil(result.bytesWritten)
        checkEqual(DiskFormat.bytes(nil), "未提供")
    }
    func testPermissionErrorIsDistinctFromUnsupportedBridge() throws {
        let result = SMARTParser.parse(try json(["smartctl": ["exit_status": 2, "messages": [["string": "Operation not permitted"]]]]))
        checkTrue(result.explanation.contains("未允许"))
        checkEqual(result.health, .unavailable)
    }
    func testCommandErrorIsNotMisreportedAsHardwareLimitation() throws {
        let result = SMARTParser.parse(try json(["smartctl": ["exit_status": 1, "messages": [["string": "UNRECOGNIZED OPTION"]]]]))
        checkTrue(result.explanation.contains("读取组件"))
    }
    func testCriticalWarningAndMediaErrorsAreSurfaced() throws {
        let result = SMARTParser.parse(try json(["smart_status": ["passed": true], "nvme_smart_health_information_log": ["critical_warning": 1, "media_errors": 2]]))
        checkEqual(result.health, .attention)
        checkTrue(result.fields.first { $0.id == "media" }?.flagged == true)
    }
    func testFailedSMARTIsNeverDisplayedAsPassed() throws {
        let result = SMARTParser.parse(try json(["smart_status": ["passed": false], "smartctl": ["exit_status": 8]]))
        checkEqual(result.health, .failed)
    }
    func testUnsafeShutdownCounterDoesNotImplyFailure() throws {
        let result = SMARTParser.parse(try json(["smart_status": ["passed": true], "nvme_smart_health_information_log": ["unsafe_shutdowns": 100]]))
        checkEqual(result.health, .passed)
    }
    func testVendorLBAAttributesAreNotBlindlyMultipliedBy512() throws {
        let result = SMARTParser.parse(try json(["smart_status": ["passed": true], "ata_smart_attributes": ["table": [["id": 241, "raw": ["value": 2429]]]]]))
        checkNil(result.bytesWritten)
    }
    func testInvalidATAStatisticsAreIgnored() throws {
        let result = SMARTParser.parse(try json(["smart_status": ["passed": true],
            "ata_smart_attributes": ["table": [["id": 5]]],
            "ata_device_statistics": ["pages": [["table": [["name": "Logical Sectors Written", "value": 1000, "flags": ["valid": false]]]]]]]))
        checkNil(result.bytesWritten)
    }
    func testAPFSTreeIncludesSynthesizedVolumesWithoutDuplicateIDs() {
        let record: [String: Any] = ["AllDisksAndPartitions": [["APFSVolumes": [["DeviceIdentifier": "disk9s1"], ["DeviceIdentifier": "disk9s2"]],
            "Partitions": [["DeviceIdentifier": "disk9s1"]]]]]
        checkEqual(DiskService.identifiers(in: record), ["disk9s1", "disk9s2"])
        checkFalse(DiskService.validDeviceID("disk1;rm -rf"))
        checkFalse(DiskService.validDeviceID("/dev/disk2"))
        checkTrue(DiskService.validDeviceID("disk9s2s1"))
    }
    func testIncompleteOrUnrelatedBenchmarkIsRejected() {
        checkThrows(try BenchmarkParser.parse("password not a benchmark"))
        checkThrows(try BenchmarkParser.parse("Sequential Read 1MiB (QD=8): 3000 MB/s"))
    }
    func testFullBenchmarkTextParsesAllQueuesAndMetadata() throws {
        let result = try BenchmarkParser.parse(Self.benchmark)
        checkEqual(result.rows.count, 4)
        checkEqual(result.rows[0].read, 3855.95)
        checkEqual(result.rows[0].queueDepth, 8)
        checkEqual(result.rows[3].write, 45.98)
        checkEqual(result.deviceName, "SanDisk Extreme Pro USB4")
        checkTrue(result.volumeName.hasPrefix("Extreme Pro"))
        checkNotNil(result.measuredAt)
    }
    func testBenchmarkRejectsDuplicateRowsAndZeroUnfinishedScores() {
        checkThrows(try BenchmarkParser.parse(Self.benchmark + "\nSequential Read 1MiB (QD=8): 100 MB/s"))
        checkThrows(try BenchmarkParser.parse(Self.benchmark.replacingOccurrences(of: "3855.95", with: "0.00")))
    }
    func testCommandRunnerDrainsLargeOutputAndEnforcesTimeout() throws {
        let result = try CommandRunner.run("/usr/bin/printf", ["hello"], timeout: 1)
        checkEqual(String(data: result.data, encoding: .utf8), "hello")
        let large = try CommandRunner.run("/bin/dd", ["if=/dev/zero", "bs=200000", "count=1"])
        checkEqual(large.data.count, 200000)
        let started = Date()
        let timed = try CommandRunner.run("/bin/sleep", ["5"], timeout: 0.1)
        checkLessThan(Date().timeIntervalSince(started), 3)
        checkNotEqual(timed.status, 0)
    }
    func testHistoryRoundTripPreservesDeviceAssociation() throws {
        var record = DeviceRecord()
        record.benchmarks = [try BenchmarkParser.parse(Self.benchmark)]
        let data = try JSONEncoder().encode(["serial:FIXTURE": record])
        let restored = try JSONDecoder().decode([String: DeviceRecord].self, from: data)
        checkEqual(restored["serial:FIXTURE"]?.benchmarks.first?.rows[0].read, 3855.95)
        checkNil(restored["serial:OTHER"])
    }
    func testPartialPermissionAndIOAreNotCalledUnsupportedLogs() throws {
        for (message, expected) in [("Permission denied", "权限不足"), ("Input/output error", "读写错误")] {
            let data = try json(["smart_status": ["passed": true], "smartctl": ["exit_status": 4,
                "output": ["Optional self tests not supported", message], "messages": [["string": message, "severity": "error"]]]])
            let s = SMARTParser.parse(data)
            checkTrue(s.partial)
            checkTrue(s.explanation.contains(expected))
            checkFalse(s.explanation.contains("不受当前接口"))
        }
        let s = SMARTParser.parse(try json(["smart_status": ["passed": true], "smartctl": ["exit_status": 4,
            "output": ["Optional self tests not supported", "Read log failed"]]]))
        checkTrue(s.explanation.contains("未能完成"))
    }
    func testConnectionUsesObservedBusRatherThanProductName() {
        let disk = makeDisk("disk10", serial: "SERIAL-A", bus: "USB")
        checkEqual(disk.connection, "USB · NVMe")
        checkFalse(disk.connection.contains("USB4"))
    }
    func testMissingAndDuplicateIdentitiesNeverMergePersistentRecords() {
        let a = makeDisk("disk10", serial: nil), b = makeDisk("disk11", serial: nil)
        checkNil(a.persistentIdentity)
        checkNil(b.persistentIdentity)
        checkNotEqual(a.identity, b.identity)
        let duplicates = DiskService.enforceUniqueIdentities([makeDisk("disk10", serial: "DUPLICATE"), makeDisk("disk11", serial: "DUPLICATE")])
        checkTrue(duplicates.allSatisfy { $0.persistentIdentity == nil })
        checkNotEqual(duplicates[0].identity, duplicates[1].identity)
        let unique = DiskService.enforceUniqueIdentities([makeDisk("disk10", serial: "SERIAL-A"), makeDisk("disk11", serial: "SERIAL-B")])
        checkTrue(unique.allSatisfy { $0.persistentIdentity != nil })
        checkNil(makeDisk("disk12", serial: "000000").persistentIdentity)
    }
    func makeDisk(_ id: String, serial: String?, bus: String = "PCI-Express") -> DiskDevice {
        var snapshot = SMARTSnapshot(); snapshot.serial = serial; snapshot.model = "SanDisk Extreme Pro USB4"; snapshot.protocolName = "NVMe"
        return DiskDevice(id: id, mediaName: "Same model", capacity: 1e12, bus: bus, solidState: true,
                          partitionMap: "GPT", volumes: [], snapshot: snapshot)
    }
    func testCatalogRequiresSeriesEvidenceAndDoesNotInventRetailSKU() {
        let e82 = makeDisk("disk1", serial: "A-82")
        checkNil(e82.profile.series)
        checkFalse(e82.profile.directlyReported)
        checkNil(e82.profile.reportedPartNumber)
        var e60 = makeDisk("disk2", serial: "A-60", bus: "USB")
        e60.snapshot.model = "SanDisk Extreme Portable SSD"; e60.snapshot.protocolName = "ATA"
        checkNil(e60.profile.series)
        e60.hardware = HardwareIdentity(usbVendorID: 0x0781, usbProductID: 0x558c)
        checkNil(e60.profile.series)
        checkFalse(e60.profile.directlyReported)
        checkNil(e60.profile.reportedPartNumber)
        e60.snapshot.protocolName = "NVMe"
        checkNil(e60.profile.series)
    }
    func testExplicitSKUWinsAndVolumeLabelCannotIdentifyBrandOrSeries() {
        var disk = makeDisk("disk1", serial: "A-1")
        disk.snapshot.model = "SanDisk SDSSDE82-4T00-G25"
        checkEqual(disk.profile.reportedPartNumber, "SDSSDE82-4T00-G25")
        checkTrue(disk.profile.directlyReported)
        disk.snapshot.model = "Generic Storage"
        disk.volumes = [DiskVolume(id: "disk1s1", uuid: nil, name: "SanDisk E82", mountPoint: "/Volumes/SanDisk E82", filesystem: "ExFAT", capacity: 1e12, free: 1e12, writable: true)]
        checkEqual(disk.profile.brand, .unknown)
        checkNil(disk.profile.series)
        disk.hardware = HardwareIdentity(usbVendorName: "SanDisk")
        checkEqual(disk.profile.brand, .sandisk)
        checkNil(disk.profile.series)
    }
    func adviceVolume(free: Double? = 3e12, writable: Bool = true) -> DiskVolume {
        DiskVolume(id: "disk1s1", uuid: "UUID-FIXTURE", name: "Fixture", mountPoint: "/Volumes/Fixture", filesystem: "ExFAT", capacity: 4e12, free: free, writable: writable)
    }
    func testAdviceVariesByObservedDeviceAndPurpose() {
        let nvme = makeDisk("disk1", serial: "A-1")
        var sata = makeDisk("disk2", serial: "A-2", bus: "USB")
        sata.snapshot.protocolName = "ATA"; sata.snapshot.model = "SanDisk Extreme Portable SSD"
        sata.hardware = HardwareIdentity(usbLinkBitsPerSecond: 5e9)
        checkEqual(BenchmarkAdvice.recommend(for: nvme, volume: adviceVolume(), purpose: .comparison).sizeMiB, 4096)
        checkEqual(BenchmarkAdvice.recommend(for: sata, volume: adviceVolume(), purpose: .comparison).sizeMiB, 1024)
        checkEqual(BenchmarkAdvice.recommend(for: nvme, volume: adviceVolume(), purpose: .quick).iterations, 1)
        checkEqual(BenchmarkAdvice.recommend(for: nvme, volume: adviceVolume(), purpose: .workingSet).sizeMiB, 16384)
        checkTrue(BenchmarkAdvice.recommend(for: nvme, volume: adviceVolume(), purpose: .workingSet).scope.contains("缓存"))
    }
    func testAdviceUsesNegotiatedUSBRateRatherThanUSB4ProductName() {
        var disk = makeDisk("disk1", serial: "A-1", bus: "USB")
        disk.hardware = HardwareIdentity(usbLinkBitsPerSecond: 5e9)
        checkEqual(disk.connection, "USB 5 Gb/s · NVMe")
        checkEqual(BenchmarkAdvice.recommend(for: disk, volume: adviceVolume(), purpose: .comparison).sizeMiB, 1024)
        disk.hardware = HardwareIdentity(usbLinkBitsPerSecond: 480e6)
        checkEqual(BenchmarkAdvice.recommend(for: disk, volume: adviceVolume(), purpose: .comparison).sizeMiB, 512)
        checkEqual(BenchmarkAdvice.recommend(for: disk, volume: adviceVolume(), purpose: .quick).sizeMiB, 256)
    }
    func testAdviceDownsizesForFreeSpaceAndBlocksUnsafeOrReadOnlyTargets() {
        var disk = makeDisk("disk1", serial: "A-1")
        let advice = BenchmarkAdvice.recommend(for: disk, volume: adviceVolume(free: 1.7 * 1_073_741_824), purpose: .comparison)
        checkEqual(advice.sizeMiB, 1024)
        checkTrue(advice.reason.contains("下调"))
        checkNotNil(BenchmarkAdvice.recommend(for: disk, volume: adviceVolume(free: 300e6), purpose: .comparison).blockedReason)
        checkNotNil(BenchmarkAdvice.recommend(for: disk, volume: adviceVolume(writable: false), purpose: .comparison).blockedReason)
        checkNotNil(BenchmarkAdvice.recommend(for: disk, volume: nil, purpose: .comparison).blockedReason)
        disk.snapshot.health = .failed
        checkNotNil(BenchmarkAdvice.recommend(for: disk, volume: adviceVolume(), purpose: .comparison).blockedReason)
    }
    func testBusySMARTChannelIsNotReportedAsPermanentUnsupportedHardware() throws {
        let s = SMARTParser.parse(try json(["smartctl": ["exit_status": 2,
            "messages": [["string": "Failed to open SMARTUserClient", "severity": "error"]]]]))
        checkEqual(s.health, .unavailable)
        checkTrue(s.explanation.contains("占用"))
        checkFalse(s.explanation.contains("未透传"))
    }
    func testManufacturerCatalogRequiresVerifiedHardwareAndKeepsSKUUnknown() {
        var disk = makeDisk("disk8", serial: "E82-UNIQUE")
        disk.hardware = HardwareIdentity(pciVendorID: 0x15b7, pciDeviceID: 0x5030)
        checkNil(disk.profile.series)
        disk.hardware?.tunnelVendorID = 0x0781; disk.hardware?.tunnelModelID = 0x55c8
        checkEqual(disk.profile.series, "E82")
        checkEqual(disk.profile.seriesSource, .manufacturer)
        checkFalse(disk.profile.directlyReported)
        checkNil(disk.profile.partNumber)
        checkNotNil(disk.profile.sourceURL)
        disk.hardware = HardwareIdentity(usbVendorID: 0x0781, usbProductID: 0x55c8)
        checkEqual(disk.profile.seriesLabel, "E82 · 官方资料匹配")
        disk.hardware?.usbProductID = 0x558c
        checkNil(disk.profile.series)
    }
    func testConfirmedLabelsSupplementIdentityWithoutOverwritingReportedModel() throws {
        var disk = makeDisk("disk4", serial: "LABEL-ONE", bus: "USB")
        disk.snapshot.model = "SanDisk Extreme Portable SSD"
        let label = try DeviceLabel(partNumber: "sdssde60-1t00-g25", source: .photo)
        let profile = DeviceCatalog.profile(for: disk, label: label)
        checkEqual(profile.series, "E60")
        checkEqual(profile.seriesSource, .label)
        checkEqual(profile.partNumber, "SDSSDE60-1T00-G25")
        checkNil(profile.reportedPartNumber)
        checkFalse(profile.directlyReported)
        checkEqual(disk.model, "SanDisk Extreme Portable SSD")
        disk.snapshot.model = "SanDisk SDSSDE82-4T00-G25"
        let direct = DeviceCatalog.profile(for: disk, label: label)
        checkEqual(direct.seriesSource, .device)
        checkEqual(direct.series, "E82")
        checkEqual(direct.partNumber, "SDSSDE82-4T00-G25")
        checkEqual(direct.confirmedLabel?.partNumber, label.partNumber)
        checkNotNil(PartNumber.conflict(for: disk, partNumber: label.partNumber))
        let manual = DeviceCatalog.profile(for: makeDisk("disk9", serial: "A"), label: try DeviceLabel(partNumber: "SDSSDE82-4T00-Z25", source: .manual))
        checkEqual(manual.seriesSource, .manual)
    }
    func testLabelCodesRequireCapacityAndOCRDoesNotInventCharacters() throws {
        checkEqual(try PartNumber.validate(" sdssde82–4t00–g25 \n", sanDisk: true), "SDSSDE82-4T00-G25")
        checkEqual(try PartNumber.validate("MU-PE2T0S/WW"), "MU-PE2T0S/WW")
        checkEqual(try PartNumber.validate("SDSSDT40-8T00-G25", sanDisk: true), "SDSSDT40-8T00-G25")
        checkEqual(try PartNumber.validate("SDSSDH3-1T00-G26", sanDisk: true), "SDSSDH3-1T00-G26")
        checkThrows(try PartNumber.validate("Nickname123", sanDisk: true))
        for value in ["E82", "SDSSDE82", "SDSSDE82-4TOO-G25", "SanDisk Extreme SSD", "SDSSDE82-4T00-G25\nS/N123"] {
            checkThrows(try PartNumber.validate(value, sanDisk: true))
        }
        checkEqual(PartNumber.sanDiskSeries("SDSSDE60-500G-G25"), "E60")
        checkEqual(PartNumber.sanDiskSeries("SDSSDE7W-1T00-G25"), "E7W")
        checkEqual(PartNumber.photoCandidates(in: ["P/N: SDSSDE82-4T00-G25", "SDSSDE82-4T00-G25", "SDSSDE60 -", "1T00 - G25"]), ["SDSSDE82-4T00-G25", "SDSSDE60-1T00-G25"])
        checkTrue(PartNumber.photoCandidates(in: ["SDSSDEB2-4T00-G25", "SDSSDE82-4TOO-G25", "SDSSDE82"]).isEmpty)
    }
    func testLabelsFollowPhysicalSerialAcrossReplugAndVolumeRename() throws {
        var old = makeDisk("disk4", serial: "INTERNAL-ONE")
        old.hardware = HardwareIdentity(serialNumber: "ENCLOSURE-ONE")
        var replug = old; replug.id = "disk16"; replug.snapshot.serial = nil
        replug.volumes = [adviceVolume()]; replug.volumes[0].name = "Renamed"
        checkEqual(old.labelIdentity, replug.labelIdentity)
        checkEqual(try DeviceLabelBinding.target(identity: old.labelIdentity, devices: [replug]).id, "disk16")
        var replacement = old; replacement.hardware?.serialNumber = "ENCLOSURE-TWO"
        checkThrows(try DeviceLabelBinding.target(identity: old.labelIdentity, devices: [replacement]))
        checkThrows(try DeviceLabelBinding.target(identity: old.labelIdentity, devices: []))
        checkThrows(try DeviceLabelBinding.target(identity: old.labelIdentity, devices: [old, replug]))
        var missing = makeDisk("disk8", serial: nil); missing.volumes = [adviceVolume()]
        checkNotNil(missing.persistentIdentity)
        checkNil(missing.labelIdentity)
        checkThrows(try DeviceLabelBinding.target(identity: missing.labelIdentity, devices: [missing]))
    }
    func testClonedEnclosureSerialsDisableLabelBinding() {
        var a = makeDisk("disk1", serial: "INTERNAL-A"), b = makeDisk("disk2", serial: "INTERNAL-B")
        a.hardware = HardwareIdentity(serialNumber: "CLONED-BRIDGE")
        b.hardware = HardwareIdentity(serialNumber: "CLONED-BRIDGE")
        checkTrue(DiskService.enforceUniqueIdentities([a,b]).allSatisfy { $0.labelIdentity == nil })
        a.hardware?.serialNumber = "000000"
        checkEqual(a.labelIdentity, "hardware:INTERNAL-A")
    }
    func testLabelStoreRoundTripIsolationAndCorruptionPreservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceLabelStore(url: directory.appendingPathComponent("device-labels.json"))
        checkTrue(try store.load().isEmpty)
        let one = try DeviceLabel(partNumber: "SDSSDE60-1T00-G25", source: .photo)
        let two = try DeviceLabel(partNumber: "SDSSDE82-4T00-Z25", source: .manual)
        try store.save(["hardware:ONE":one,"hardware:TWO":two])
        var reopened = try DeviceLabelStore(url: store.url).load()
        checkEqual(reopened["hardware:ONE"], one)
        checkEqual(reopened["hardware:TWO"], two)
        checkNil(reopened["hardware:THREE"])
        reopened.removeValue(forKey: "hardware:ONE"); try store.save(reopened)
        checkEqual(try store.load()["hardware:TWO"], two)
        checkNil(try store.load()["hardware:ONE"])
        let broken = Data("{corrupted-do-not-overwrite".utf8)
        try broken.write(to: store.url)
        checkThrows(try store.load())
        checkEqual(try Data(contentsOf: store.url), broken)
        let invalidStore = DeviceLabelStore(url: directory)
        checkThrows(try invalidStore.save(["hardware:ONE":one]))
    }
    func testReportKeepsDeviceNameAndExplicitLabelSources() throws {
        var disk = makeDisk("disk1", serial: "A-1")
        disk.hardware = HardwareIdentity(usbVendorID: 0x0781, usbProductID: 0x55c8)
        let report = ReportBuilder.text(for: disk, label: try DeviceLabel(partNumber: "SDSSDE82-4T00-Z25", source: .photo))
        checkTrue(report.contains("型号：SanDisk Extreme Pro USB4"))
        checkTrue(report.contains("产品系列：E82 · 官方资料匹配"))
        checkTrue(report.contains("标识来源：标签确认"))
        checkTrue(report.contains("盘身型号 / 料号：SDSSDE82-4T00-Z25"))
        checkFalse(ReportBuilder.text(for: disk).contains("SDSSDE82-4T00"))
    }
    func testUSB4LinkParsingRequiresDeviceUIDAndObservedSpeed() throws {
        func node(_ uid: String, speed: String) -> [String:Any] {
            ["switch_uid_key":uid,"mode_key":"usb_four", "receptacle_upstream_ambiguous_tag":["current_speed_key":speed]]
        }
        let uid = "0123456789ABCDEF"
        let map = try ThunderboltLinkIndex.parse(json(["SPThunderboltDataType":[node("0x"+uid,speed:"40 Gb/s"), node("0x1122",speed:"20 Gb/s")]]))
        checkEqual(map[uid], 40e9)
        checkEqual(map["0000000000001122"], 20e9)
        checkTrue(try ThunderboltLinkIndex.parse(json(["x":[node("0x1122",speed:"40 Gb/s"),node("0x1122",speed:"20 Gb/s")]])).isEmpty)
        checkTrue(try ThunderboltLinkIndex.parse(json(["x":node("0x1122",speed:"Up to 40")])).isEmpty)
        checkNil(ThunderboltLinkIndex.normalizeUID("not-hex"))
        var disk = makeDisk("disk8", serial: "E82")
        disk.hardware = HardwareIdentity(transportName: "USB4", transportLinkBitsPerSecond: map[uid])
        checkEqual(disk.connection, "USB4 40 Gb/s · NVMe")
        disk.hardware?.transportLinkBitsPerSecond = nil
        checkEqual(disk.connection, "USB4 · NVMe")
    }
    func testLocalVisionOCRReadsSyntheticLabelAndRejectsNonImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for code in ["SDSSDE82-4T00", "SDSSDE82-4T00-G25"] {
        let url = directory.appendingPathComponent("synthetic-\(code).png")
        let context = try require(CGContext(data: nil, width: 1500, height: 420, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x:0,y:0,width:1500,height:420))
        for (text,y,size) in [("SYNTHETIC TEST LABEL",310.0,32.0),(code,190.0,64.0),("S/N: FIXTURE-NOT-A-DEVICE",80.0,32.0)] {
            let attributed = NSAttributedString(string:text, attributes:[
                NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Menlo" as CFString,size,nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)])
            context.textPosition = CGPoint(x:45,y:y); CTLineDraw(CTLineCreateWithAttributedString(attributed),context)
        }
        let image = try require(context.makeImage())
        let destination = try require(CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,nil); checkTrue(CGImageDestinationFinalize(destination))
        checkEqual(try LabelPhotoReader.recognize(url:url),[code])
        let fixtureKey = code == "SDSSDE82-4T00" ? "PORTABLE_DISK_TEST_BASE_PHOTO_FIXTURE" : "PORTABLE_DISK_TEST_PHOTO_FIXTURE"
        if let fixture = ProcessInfo.processInfo.environment[fixtureKey] {
            try Data(contentsOf:url).write(to:URL(fileURLWithPath:fixture))
        }
        }
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to:invalid)
        checkThrows(try LabelPhotoReader.recognize(url:invalid))
    }
    func testBareLabelModelsAndOptionalSKUSuffixes() throws {
        for code in ["SDSSDE82-4T00", "SDSSDE82-4T00-G25", "SDSSDE60-1T00", "SDSSDE60-500G", "SDSSDT40-8T00", "SDSSDH3-1T00"] {
            checkEqual(try PartNumber.validate(code, sanDisk: true), code)
        }
        checkEqual(try PartNumber.validate(" sdssde82–4t00 ", sanDisk: true), "SDSSDE82-4T00")
        checkEqual(PartNumber.sanDiskSeries("SDSSDE82-4T00"), "E82")
        checkEqual(PartNumber.baseModel("SDSSDE82-4T00-G25"), "SDSSDE82-4T00")
        checkNil(PartNumber.sanDiskRetail("SDSSDE82-4T00"))
        checkEqual(PartNumber.sanDiskRetail("SDSSDE82-4T00-G25"), "SDSSDE82-4T00-G25")
        var disk = makeDisk("disk8", serial: "MODEL-FIXTURE")
        disk.snapshot.model = "SanDisk SDSSDE82-4T00"
        checkEqual(disk.profile.reportedPartNumber, "SDSSDE82-4T00")
        checkEqual(disk.profile.seriesSource, .device)
        checkTrue(disk.profile.directlyReported)
        checkEqual(disk.model, "SanDisk SDSSDE82-4T00")
    }
    func testBaseModelAndMatchingSKUDoNotCreateFalseConflicts() {
        var disk = makeDisk("disk8", serial: "MODEL-FIXTURE")
        disk.snapshot.model = "SDSSDE82-4T00-G25"
        checkNil(PartNumber.conflict(for: disk, partNumber: "SDSSDE82-4T00"))
        checkNotNil(PartNumber.conflict(for: disk, partNumber: "SDSSDE82-4T00-Z25"))
        disk.snapshot.model = "SDSSDE82-4T00"
        checkNil(PartNumber.conflict(for: disk, partNumber: "SDSSDE82-4T00-G25"))
        checkNotNil(PartNumber.conflict(for: disk, partNumber: "SDSSDE82-2T00"))
        checkNotNil(PartNumber.conflict(for: disk, partNumber: "SDSSDE60-1T00"))
        disk.snapshot.model = "SDSSDE82"
        checkNil(disk.profile.reportedPartNumber)
        checkEqual(disk.profile.series, "E82")
    }
    func testBareModelPersistenceAndReportNeverInventSuffix() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceLabelStore(url: directory.appendingPathComponent("device-labels.json"))
        let bare = try DeviceLabel(partNumber: "SDSSDE82-4T00", source: .manual)
        let oldSKU = try DeviceLabel(partNumber: "SDSSDE60-1T00-G25", source: .photo)
        try store.save(["hardware:BARE-FIXTURE": bare, "hardware:OLD-FIXTURE": oldSKU])
        let reopened = try DeviceLabelStore(url: store.url).load()
        checkEqual(reopened["hardware:BARE-FIXTURE"], bare)
        checkEqual(reopened["hardware:OLD-FIXTURE"], oldSKU)
        let disk = makeDisk("disk8", serial: "BARE-FIXTURE")
        let profile = DeviceCatalog.profile(for: disk, label: reopened["hardware:BARE-FIXTURE"])
        checkEqual(profile.partNumber, "SDSSDE82-4T00")
        checkEqual(profile.series, "E82")
        checkEqual(profile.partNumberSource, .manual)
        let report = ReportBuilder.text(for: disk, label: bare)
        checkTrue(report.contains("盘身型号 / 料号：SDSSDE82-4T00\n"))
        checkFalse(report.contains("SDSSDE82-4T00-"))
        checkEqual(disk.model, "SanDisk Extreme Pro USB4")
    }
    func testOCRAcceptsLabelModelWithoutTruncatingInvalidSuffix() {
        checkEqual(PartNumber.photoCandidates(in: ["Model: SDSSDE82-4T00", "P/N: SDSSDE82-4T00-G25"]), ["SDSSDE82-4T00", "SDSSDE82-4T00-G25"])
        checkEqual(PartNumber.photoCandidates(in: ["Model: SDSSDE82 - 4T00", "S/N: SYNTHETIC"]), ["SDSSDE82-4T00"])
        for invalid in ["SDSSDE82-4T00-", "SDSSDE82-4T00-G", "SDSSDE82-4T00-G25EXTRALONG", "XSDSSDE82-4T00", "SDSSDE82-4T00-G25-EXTRA", "SDSSDE82-4T00 -"] {
            checkTrue(PartNumber.photoCandidates(in: [invalid]).isEmpty)
        }
    }
    // Synthetic parser fixture using the user's reported scores; never seeds the application UI or history.
    static let benchmark = """
    AmorphousDiskMark 4.0.1
    Sequential Read 1MiB (QD=   8) : 3855.95 MB/s [1 IOPS]
    Sequential Write 1MiB (QD=   8) : 3569.71 MB/s [1 IOPS]
    Sequential Read 1MiB (QD=1) : 3211.74 MB/s [1 IOPS]
    Sequential Write 1MiB (QD=1) : 3164.90 MB/s [1 IOPS]
    Random Read 4KiB (QD=  64) : 890.63 MB/s [1 IOPS]
    Random Write 4KiB (QD=  64) : 348.66 MB/s [1 IOPS]
    Random Read 4KiB (QD=1) : 73.39 MB/s [1 IOPS]
    Random Write 4KiB (QD=1) : 45.98 MB/s [1 IOPS]
    Test : 4 GiB (x3) [Interval=5 sec]
    Volume : Extreme Pro: 1% used (1/3725 GiB)
    Device : SanDisk Extreme Pro USB4
    Date : 2026-11-20T17:00:00Z
    """
}


// Standalone checks run on Command Line Tools without Xcode-only test plugins.
private enum Checks {
    static var failures = 0
    static var assertions = 0
    static func record(_ passed: Bool, _ description: String, file: StaticString, line: UInt) {
        assertions += 1
        if !passed { failures += 1; print("FAIL \(file):\(line): \(description)") }
    }
}
private struct CheckFailure: Error {}
private func checkEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { Checks.record(a == b, "\(a) != \(b)", file: file, line: line) }
private func checkNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { Checks.record(a != b, "Values unexpectedly equal", file: file, line: line) }
private func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { Checks.record(value, "Expected true", file: file, line: line) }
private func checkFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { Checks.record(!value, "Expected false", file: file, line: line) }
private func checkNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { Checks.record(value == nil, "Expected nil", file: file, line: line) }
private func checkNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { Checks.record(value != nil, "Expected non-nil", file: file, line: line) }
private func checkGreaterThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { Checks.record(a > b, "Expected \(a) > \(b)", file: file, line: line) }
private func checkLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { Checks.record(a < b, "Expected \(a) < \(b)", file: file, line: line) }
private func require<T>(_ value: T?) throws -> T { guard let value else { throw CheckFailure() }; return value }
private func checkThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); Checks.record(false, "Expected thrown error", file: file, line: line) }
    catch { Checks.record(true, "", file: file, line: line) }
}
@main enum CheckRunner {
    static func main() {
        let suite = DiskCoreTests()
        let cases: [(String, () throws -> Void)] = [
            ("testRealNVMeFixtureAndStandardUnits", suite.testRealNVMeFixtureAndStandardUnits),
            ("testRealATAFixturePartialLogsAreNotHealthFailure", suite.testRealATAFixturePartialLogsAreNotHealthFailure),
            ("testMissingMetricsDoNotBecomeZeroOrHealthy", suite.testMissingMetricsDoNotBecomeZeroOrHealthy),
            ("testPermissionErrorIsDistinctFromUnsupportedBridge", suite.testPermissionErrorIsDistinctFromUnsupportedBridge),
            ("testCommandErrorIsNotMisreportedAsHardwareLimitation", suite.testCommandErrorIsNotMisreportedAsHardwareLimitation),
            ("testCriticalWarningAndMediaErrorsAreSurfaced", suite.testCriticalWarningAndMediaErrorsAreSurfaced),
            ("testFailedSMARTIsNeverDisplayedAsPassed", suite.testFailedSMARTIsNeverDisplayedAsPassed),
            ("testUnsafeShutdownCounterDoesNotImplyFailure", suite.testUnsafeShutdownCounterDoesNotImplyFailure),
            ("testVendorLBAAttributesAreNotBlindlyMultipliedBy512", suite.testVendorLBAAttributesAreNotBlindlyMultipliedBy512),
            ("testInvalidATAStatisticsAreIgnored", suite.testInvalidATAStatisticsAreIgnored),
            ("testAPFSTreeIncludesSynthesizedVolumesWithoutDuplicateIDs", suite.testAPFSTreeIncludesSynthesizedVolumesWithoutDuplicateIDs),
            ("testIncompleteOrUnrelatedBenchmarkIsRejected", suite.testIncompleteOrUnrelatedBenchmarkIsRejected),
            ("testFullBenchmarkTextParsesAllQueuesAndMetadata", suite.testFullBenchmarkTextParsesAllQueuesAndMetadata),
            ("testBenchmarkRejectsDuplicateRowsAndZeroUnfinishedScores", suite.testBenchmarkRejectsDuplicateRowsAndZeroUnfinishedScores),
            ("testCommandRunnerDrainsLargeOutputAndEnforcesTimeout", suite.testCommandRunnerDrainsLargeOutputAndEnforcesTimeout),
            ("testHistoryRoundTripPreservesDeviceAssociation", suite.testHistoryRoundTripPreservesDeviceAssociation),
            ("testPartialPermissionAndIOAreNotCalledUnsupportedLogs", suite.testPartialPermissionAndIOAreNotCalledUnsupportedLogs),
            ("testConnectionUsesObservedBusRatherThanProductName", suite.testConnectionUsesObservedBusRatherThanProductName),
            ("testMissingAndDuplicateIdentitiesNeverMergePersistentRecords", suite.testMissingAndDuplicateIdentitiesNeverMergePersistentRecords),
            ("testCatalogRequiresSeriesEvidenceAndDoesNotInventRetailSKU", suite.testCatalogRequiresSeriesEvidenceAndDoesNotInventRetailSKU),
            ("testExplicitSKUWinsAndVolumeLabelCannotIdentifyBrandOrSeries", suite.testExplicitSKUWinsAndVolumeLabelCannotIdentifyBrandOrSeries),
            ("testAdviceVariesByObservedDeviceAndPurpose", suite.testAdviceVariesByObservedDeviceAndPurpose),
            ("testAdviceUsesNegotiatedUSBRateRatherThanUSB4ProductName", suite.testAdviceUsesNegotiatedUSBRateRatherThanUSB4ProductName),
            ("testAdviceDownsizesForFreeSpaceAndBlocksUnsafeOrReadOnlyTargets", suite.testAdviceDownsizesForFreeSpaceAndBlocksUnsafeOrReadOnlyTargets),
            ("testBusySMARTChannelIsNotReportedAsPermanentUnsupportedHardware", suite.testBusySMARTChannelIsNotReportedAsPermanentUnsupportedHardware),
            ("testManufacturerCatalogRequiresVerifiedHardwareAndKeepsSKUUnknown", suite.testManufacturerCatalogRequiresVerifiedHardwareAndKeepsSKUUnknown),
            ("testConfirmedLabelsSupplementIdentityWithoutOverwritingReportedModel", suite.testConfirmedLabelsSupplementIdentityWithoutOverwritingReportedModel),
            ("testLabelCodesRequireCapacityAndOCRDoesNotInventCharacters", suite.testLabelCodesRequireCapacityAndOCRDoesNotInventCharacters),
            ("testLabelsFollowPhysicalSerialAcrossReplugAndVolumeRename", suite.testLabelsFollowPhysicalSerialAcrossReplugAndVolumeRename),
            ("testClonedEnclosureSerialsDisableLabelBinding", suite.testClonedEnclosureSerialsDisableLabelBinding),
            ("testLabelStoreRoundTripIsolationAndCorruptionPreservation", suite.testLabelStoreRoundTripIsolationAndCorruptionPreservation),
            ("testReportKeepsDeviceNameAndExplicitLabelSources", suite.testReportKeepsDeviceNameAndExplicitLabelSources),
            ("testUSB4LinkParsingRequiresDeviceUIDAndObservedSpeed", suite.testUSB4LinkParsingRequiresDeviceUIDAndObservedSpeed),
            ("testLocalVisionOCRReadsSyntheticLabelAndRejectsNonImages", suite.testLocalVisionOCRReadsSyntheticLabelAndRejectsNonImages),
            ("testBareLabelModelsAndOptionalSKUSuffixes", suite.testBareLabelModelsAndOptionalSKUSuffixes),
            ("testBaseModelAndMatchingSKUDoNotCreateFalseConflicts", suite.testBaseModelAndMatchingSKUDoNotCreateFalseConflicts),
            ("testBareModelPersistenceAndReportNeverInventSuffix", suite.testBareModelPersistenceAndReportNeverInventSuffix),
            ("testOCRAcceptsLabelModelWithoutTruncatingInvalidSuffix", suite.testOCRAcceptsLabelModelWithoutTruncatingInvalidSuffix)
        ]
        for (name, run) in cases {
            let before = Checks.failures
            do { try run() } catch { Checks.failures += 1; print("FAIL \(name): \(error)") }
            if Checks.failures == before { print("PASS \(name)") }
        }
        print("\(cases.count) checks, \(Checks.assertions) assertions, \(Checks.failures) failures")
        exit(Checks.failures == 0 ? 0 : 1)
    }
}
