import Foundation
import SwiftUI
import AVFoundation
import os

@MainActor
class TranscriptionServiceRegistry {
    private let whisperState: WhisperState
    private let modelsDirectory: URL
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = LocalTranscriptionService(
        modelsDirectory: modelsDirectory,
        whisperState: whisperState
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: whisperState.modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var parakeetTranscriptionService = ParakeetTranscriptionService()

    init(whisperState: WhisperState, modelsDirectory: URL) {
        self.whisperState = whisperState
        self.modelsDirectory = modelsDirectory
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .local:
            return localTranscriptionService
        case .parakeet:
            return parakeetTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return cloudTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let service = service(for: model.provider)
        logger.debug("Transcribing with \(model.displayName) using \(String(describing: type(of: service)))")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    /// Transcribe audio and return the text (uses current model)
    func transcribe(audioURL: URL) async throws -> String {
        guard let model = await whisperState.currentTranscriptionModel else {
            throw WhisperStateError.modelLoadFailed
        }
        return try await transcribe(audioURL: audioURL, model: model)
    }

    /// Transcribe audio with timestamps (for diarization)
    /// Currently only supports local Whisper models
    func transcribeWithTimestamps(audioURL: URL) async throws -> [WhisperTimestampedSegment] {
        guard let model = await whisperState.currentTranscriptionModel else {
            throw WhisperStateError.modelLoadFailed
        }

        // Currently only local transcription supports timestamps
        guard model.provider == .local else {
            logger.warning("Timestamped transcription only supported for local models, falling back to simple transcription")
            let text = try await transcribe(audioURL: audioURL, model: model)
            // Return single segment with full duration
            let asset = AVURLAsset(url: audioURL)
            let duration = try await CMTimeGetSeconds(asset.load(.duration))
            return [WhisperTimestampedSegment(text: text, startTime: 0, endTime: duration)]
        }

        return try await localTranscriptionService.transcribeWithTimestamps(audioURL: audioURL, model: model)
    }

    func cleanup() {
        parakeetTranscriptionService.cleanup()
    }
}
