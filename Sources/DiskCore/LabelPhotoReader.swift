import Foundation
import Vision
import ImageIO
import CoreML

public enum LabelPhotoError: LocalizedError {
    case tooLarge, unreadable, noNumber, timedOut
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "照片超过 50 MB，请选择清晰的标签近照后重试。"
        case .unreadable: return "这张照片无法读取。请选择 PNG、JPEG、HEIC 或 TIFF 图片。"
        case .noNumber: return "没有识别到完整的 SDSSDE 料号。请换一张清晰的标签近照，或手动填写；不会猜测模糊字符。"
        case .timedOut: return "照片识别超时，请换一张清晰的标签近照重试，也可以直接手动填写。"
        }
    }
}

public enum LabelPhotoReader {
    private static let queue = DispatchQueue(label: "com.glow.portabledisktest.label-recognition", qos: .userInitiated)
    public static func recognizeAsync(url: URL) async throws -> [String] {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try recognize(url: url)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    public static func recognize(url: URL) throws -> [String] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 50_000_000 else { throw LabelPhotoError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { throw LabelPhotoError.unreadable }
        let request = VNRecognizeTextRequest()
        // ASCII part numbers do not need the newer multilingual ANE OCR pipeline.
        // Revision 2 remains supported on the macOS 14 deployment target.
        if VNRecognizeTextRequest.supportedRevisions.contains(VNRecognizeTextRequestRevision2) {
            request.revision = VNRecognizeTextRequestRevision2
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.005
        // Small, occasional labels do not need ANE model compilation. On the Apple Silicon validation Mac mini
        // macOS 27 the ANE compiler stalled in the release app; use supported CPU stages.
        for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        let start = Date()
        let deadline = DispatchWorkItem { request.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: deadline)
        defer { deadline.cancel() }
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
        catch {
            if Date().timeIntervalSince(start) >= 20 { throw LabelPhotoError.timedOut }
            throw error
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let numbers = PartNumber.photoCandidates(in: lines)
        guard !numbers.isEmpty else { throw LabelPhotoError.noNumber }
        return numbers
    }
}
