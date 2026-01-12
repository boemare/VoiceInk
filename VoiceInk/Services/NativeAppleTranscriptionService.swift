import Foundation
import AVFoundation
import os

#if canImport(Speech)
import Speech
#endif

/// Transcription service that leverages the new SpeechAnalyzer / SpeechTranscriber API available on macOS 26 (Tahoe).
/// Falls back with an unsupported-provider error on earlier OS versions so the application can gracefully degrade.
class NativeAppleTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NativeAppleTranscriptionService")
    
    /// Maps simple language codes to Apple's BCP-47 locale format
    private func mapToAppleLocale(_ simpleCode: String) -> String {
        let mapping = [
            "en": "en-US",
            "es": "es-ES", 
            "fr": "fr-FR",
            "de": "de-DE",
            "ar": "ar-SA",
            "it": "it-IT",
            "ja": "ja-JP",
            "ko": "ko-KR",
            "pt": "pt-BR",
            "yue": "yue-CN",
            "zh": "zh-CN"
        ]
        return mapping[simpleCode] ?? "en-US"
    }
    
    enum ServiceError: Error, LocalizedError {
        case unsupportedOS
        case transcriptionFailed
        case localeNotSupported
        case invalidModel
        case assetAllocationFailed
        
        var errorDescription: String? {
            switch self {
            case .unsupportedOS:
                return "SpeechAnalyzer requires macOS 26 or later."
            case .transcriptionFailed:
                return "Transcription failed using SpeechAnalyzer."
            case .localeNotSupported:
                return "The selected language is not supported by SpeechAnalyzer."
            case .invalidModel:
                return "Invalid model type provided for Native Apple transcription."
            case .assetAllocationFailed:
                return "Failed to allocate assets for the selected locale."
            }
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard model is NativeAppleModel else {
            throw ServiceError.invalidModel
        }
        
        guard #available(macOS 26, *) else {
            logger.error("SpeechAnalyzer is not available on this macOS version")
            throw ServiceError.unsupportedOS
        }
        
        // Native Apple transcription requires macOS 26+ APIs that are not yet available
        logger.notice("Native Apple transcription is disabled in this build (macOS 26 APIs not available).")
        throw ServiceError.unsupportedOS
    }
    
    
    
} 
