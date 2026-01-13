import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import os

class ScreenRecordingService: NSObject, ObservableObject {
    @MainActor @Published var isRecording = false
    @MainActor @Published var recordingError: String?

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var frameCount = 0
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ScreenRecording")

    private let videoQueue = DispatchQueue(label: "com.voiceink.screen.video", qos: .userInitiated)
    private let writerLock = NSLock()

    private let dosRecordingsDirectory: URL

    override init() {
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        self.dosRecordingsDirectory = appSupportDirectory.appendingPathComponent("DosRecordings")
        super.init()
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: dosRecordingsDirectory, withIntermediateDirectories: true)
    }

    /// Check if the app has screen recording permission
    static func hasScreenRecordingPermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    @MainActor
    func startRecording() async throws -> URL {
        guard !isRecording else {
            throw ScreenRecordingError.alreadyRecording
        }

        // Check permission first
        let hasPermission = await Self.hasScreenRecordingPermission()
        if !hasPermission {
            logger.error("Screen recording permission not granted")
            throw ScreenRecordingError.noPermission
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw ScreenRecordingError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = display.width * 2
        configuration.height = display.height * 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let fileName = "\(UUID().uuidString).mov"
        outputURL = dosRecordingsDirectory.appendingPathComponent(fileName)

        guard let outputURL = outputURL else {
            throw ScreenRecordingError.invalidURL
        }

        try setupAssetWriter(width: configuration.width, height: configuration.height, url: outputURL)

        stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        guard let stream = stream else {
            throw ScreenRecordingError.streamCreationFailed
        }

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)

        try await stream.startCapture()
        isRecording = true
        sessionStarted = false
        frameCount = 0

        logger.info("Screen recording started: \(outputURL.path)")
        logger.info("Display size: \(display.width)x\(display.height), recording at \(configuration.width)x\(configuration.height)")

        return outputURL
    }

    @MainActor
    func stopRecording() async throws -> URL? {
        guard isRecording else { return nil }

        isRecording = false

        do {
            try await stream?.stopCapture()
        } catch {
            logger.warning("Error stopping capture: \(error.localizedDescription)")
        }

        stream = nil

        // Check if any frames were captured before finalizing
        let capturedFrames = frameCount
        if capturedFrames == 0 {
            logger.error("❌ No frames captured during recording")
            // Clean up empty file
            if let url = outputURL {
                try? FileManager.default.removeItem(at: url)
            }
            throw ScreenRecordingError.noFramesCaptured
        }

        await finishWriting()

        logger.info("Screen recording stopped: \(self.outputURL?.path ?? "nil"), frames captured: \(capturedFrames)")

        return outputURL
    }

    private func setupAssetWriter(width: Int, height: Int, url: URL) throws {
        writerLock.lock()
        defer { writerLock.unlock() }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
            assetWriter?.add(videoInput)
        }

        assetWriter?.startWriting()
        sessionStarted = false
    }

    private func finishWriting() async {
        writerLock.lock()

        videoInput?.markAsFinished()

        let writer = assetWriter
        writerLock.unlock()

        if writer?.status == .writing {
            await writer?.finishWriting()
        }

        writerLock.lock()
        if let status = assetWriter?.status, status == .failed {
            logger.error("Asset writer failed: \(self.assetWriter?.error?.localizedDescription ?? "unknown")")
        }

        assetWriter = nil
        videoInput = nil
        sessionStarted = false
        writerLock.unlock()
    }

    func extractThumbnail(from videoURL: URL) -> Data? {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 200, height: 150)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return nsImage.tiffRepresentation
        } catch {
            logger.warning("Failed to extract thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
}

extension ScreenRecordingService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.recordingError = error.localizedDescription
            self.isRecording = false
        }
        logger.error("Stream stopped with error: \(error.localizedDescription)")
    }
}

extension ScreenRecordingService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            logger.warning("Sample buffer not ready")
            return
        }

        switch type {
        case .screen:
            processVideoSampleBuffer(sampleBuffer)
        case .audio, .microphone:
            break
        @unknown default:
            logger.warning("Unknown stream output type")
            break
        }
    }

    private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerLock.lock()
        defer { writerLock.unlock() }

        guard let videoInput = videoInput,
              let assetWriter = assetWriter,
              assetWriter.status == .writing else {
            let hasInput = self.videoInput != nil
            let hasWriter = self.assetWriter != nil
            let status = self.assetWriter?.status.rawValue ?? -1
            logger.warning("Cannot process frame: videoInput=\(hasInput), assetWriter=\(hasWriter), status=\(status)")
            return
        }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: timestamp)
            sessionStarted = true
            logger.info("Session started at timestamp: \(timestamp.seconds)")
        }

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
            frameCount += 1
            if frameCount == 1 || frameCount % 30 == 0 {
                logger.info("Captured frame \(self.frameCount)")
            }
        }
    }
}

enum ScreenRecordingError: LocalizedError {
    case noPermission
    case noDisplayFound
    case invalidURL
    case alreadyRecording
    case streamCreationFailed
    case recordingFailed(String)
    case noFramesCaptured

    var errorDescription: String? {
        switch self {
        case .noPermission: return "Screen recording permission not granted. Enable in System Settings > Privacy & Security > Screen Recording"
        case .noDisplayFound: return "No display found for screen recording"
        case .invalidURL: return "Invalid output URL"
        case .alreadyRecording: return "Recording is already in progress"
        case .streamCreationFailed: return "Failed to create screen capture stream"
        case .recordingFailed(let msg): return "Recording failed: \(msg)"
        case .noFramesCaptured: return "No frames captured - check screen recording permission"
        }
    }
}
