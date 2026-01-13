import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os

// MARK: - Recording State Machine
enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case enhancing
    case busy
}

@MainActor
class WhisperState: NSObject, ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var isModelLoaded = false
    @Published var loadedLocalModel: WhisperModel?
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var isModelLoading = false
    @Published var availableModels: [WhisperModel] = []
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
    @Published var clipboardMessage = ""
    @Published var miniRecorderError: String?
    @Published var shouldCancelRecording = false
    @Published var isNotesMode = false  // Set by HotkeyManager for tap-tap mode to save as note
    @Published var isDosMode = false  // Set by HotkeyManager for Shift+tap-tap mode to save as Do with screen recording


    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            if isMiniRecorderVisible {
                if oldValue == "notch" {
                    notchWindowManager?.hide()
                    notchWindowManager = nil
                } else {
                    miniWindowManager?.hide()
                    miniWindowManager = nil
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    showRecorderPanel()
                }
            }
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
        }
    }
    
    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }
    
    var whisperContext: WhisperContext?
    let recorder = Recorder()
    let screenRecordingService = ScreenRecordingService()
    var recordedFile: URL? = nil
    var recordedVideoFile: URL? = nil
    let whisperPrompt = WhisperPrompt()
    
    // Prompt detection service for trigger word handling
    private let promptDetectionService = PromptDetectionService()
    
    let modelContext: ModelContext
    
    internal var serviceRegistry: TranscriptionServiceRegistry!
    
    private var modelUrl: URL? {
        let possibleURLs = [
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "Models"),
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin"),
            Bundle.main.bundleURL.appendingPathComponent("Models/ggml-base.en.bin")
        ]
        
        for url in possibleURLs {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
    
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    
    let modelsDirectory: URL
    let recordingsDirectory: URL
    let enhancementService: AIEnhancementService?
    var licenseViewModel: LicenseViewModel
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?
    
    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    @Published var parakeetDownloadStates: [String: Bool] = [:]
    
    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        
        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
        
        super.init()
        
        // Configure the session manager
        if let enhancementService = enhancementService {
            PowerModeSessionManager.shared.configure(whisperState: self, enhancementService: enhancementService)
        }

        // Initialize the transcription service registry
        self.serviceRegistry = TranscriptionServiceRegistry(whisperState: self, modelsDirectory: self.modelsDirectory)
        
        setupNotifications()
        createModelsDirectoryIfNeeded()
        createRecordingsDirectoryIfNeeded()
        loadAvailableModels()
        loadCurrentTranscriptionModel()
        refreshAllAvailableModels()
    }
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }
    
    func toggleRecord(powerModeId: UUID? = nil) async {
        if recordingState == .recording {
            await recorder.stopRecording()

            // Stop screen recording if it was active (Dos mode)
            if screenRecordingService.isRecording {
                recordedVideoFile = try? await screenRecordingService.stopRecording()
            }

            if let recordedFile {
                if !shouldCancelRecording {
                    let audioAsset = AVURLAsset(url: recordedFile)
                    let duration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0

                    let transcription = Transcription(
                        text: "",
                        duration: duration,
                        audioFileURL: recordedFile.absoluteString,
                        transcriptionStatus: .pending
                    )
                    modelContext.insert(transcription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

                    await transcribeAudio(on: transcription)
                } else {
                    await MainActor.run {
                        recordingState = .idle
                    }
                    await cleanupModelResources()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
                await MainActor.run {
                    recordingState = .idle
                }
            }
        } else {
            guard currentTranscriptionModel != nil else {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "No AI Model Selected",
                        type: .error
                    )
                }
                return
            }
            shouldCancelRecording = false
            requestRecordPermission { [self] granted in
                if granted {
                    Task {
                        do {
                            // --- Prepare permanent file URL ---
                            let fileName = "\(UUID().uuidString).wav"
                            let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
                            self.recordedFile = permanentURL

                            try await self.recorder.startRecording(toOutputFile: permanentURL)

                            await MainActor.run {
                                self.recordingState = .recording
                            }

                            // Detect and apply Power Mode for current app/website in background
                            Task {
                                await ActiveWindowService.shared.applyConfiguration(powerModeId: powerModeId)
                            }

                            // Load model and capture context in background without blocking
                            Task.detached { [weak self] in
                                guard let self = self else { return }

                                // Only load model if it's a local model and not already loaded
                                if let model = await self.currentTranscriptionModel, model.provider == .local {
                                    if let localWhisperModel = await self.availableModels.first(where: { $0.name == model.name }),
                                       await self.whisperContext == nil {
                                        do {
                                            try await self.loadModel(localWhisperModel)
                                        } catch {
                                            await self.logger.error("❌ Model loading failed: \(error.localizedDescription)")
                                        }
                                    }
                                } else if let parakeetModel = await self.currentTranscriptionModel as? ParakeetModel {
                                    try? await self.serviceRegistry.parakeetTranscriptionService.loadModel(for: parakeetModel)
                                }

                                if let enhancementService = await self.enhancementService {
                                    await MainActor.run {
                                        enhancementService.captureClipboardContext()
                                    }
                                    await enhancementService.captureScreenContext()
                                }
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription)")
                            await NotificationManager.shared.showNotification(title: "Recording failed to start", type: .error)
                            await self.dismissMiniRecorder()
                            // Do not remove the file on a failed start, to preserve all recordings.
                            self.recordedFile = nil
                        }
                    }
                } else {
                    logger.error("❌ Recording permission denied.")
                }
            }
        }
    }
    
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        response(true)
    }
    
    private func transcribeAudio(on transcription: Transcription) async {
        guard let urlString = transcription.audioFileURL, let url = URL(string: urlString) else {
            logger.error("❌ Invalid audio file URL in transcription object.")
            await MainActor.run {
                recordingState = .idle
            }
            transcription.text = "Transcription Failed: Invalid audio file URL"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            return
        }

        if shouldCancelRecording {
            await MainActor.run {
                recordingState = .idle
            }
            await cleanupModelResources()
            return
        }

        await MainActor.run {
            recordingState = .transcribing
        }

        // Play stop sound when transcription starts with a small delay
        Task {
            let isSystemMuteEnabled = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled")
            if isSystemMuteEnabled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200 milliseconds delay
            }
            await MainActor.run {
                SoundManager.shared.playStopSound()
            }
        }

        defer {
            if shouldCancelRecording {
                Task {
                    await cleanupModelResources()
                }
            }
        }

        logger.notice("🔄 Starting transcription...")
        
        var finalPastedText: String?
        var promptDetectionResult: PromptDetectionService.PromptDetectionResult?

        do {
            guard let model = currentTranscriptionModel else {
                throw WhisperStateError.transcriptionFailed
            }

            let transcriptionStart = Date()
            var text = try await serviceRegistry.transcribe(audioURL: url, model: model)
            logger.notice("📝 Raw transcript: \(text, privacy: .public)")
            text = TranscriptionOutputFilter.filter(text)
            logger.notice("📝 Output filter result: \(text, privacy: .public)")
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            let powerModeManager = PowerModeManager.shared
            let activePowerModeConfig = powerModeManager.currentActiveConfiguration
            let powerModeName = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.name : nil
            let powerModeEmoji = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.emoji : nil

            if await checkCancellationAndCleanup() { return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if UserDefaults.standard.object(forKey: "IsTextFormattingEnabled") as? Bool ?? true {
                text = WhisperTextFormatter.format(text)
                logger.notice("📝 Formatted transcript: \(text, privacy: .public)")
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            logger.notice("📝 WordReplacement: \(text, privacy: .public)")

            text = FillerWordFilterService.shared.removeFillerWords(from: text)
            logger.notice("📝 FillerWordFilter: \(text, privacy: .public)")

            text = SnippetService.shared.applySnippets(to: text, using: modelContext)
            logger.notice("📝 SnippetExpansion: \(text, privacy: .public)")

            let audioAsset = AVURLAsset(url: url)
            let actualDuration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0
            
            transcription.text = text
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            transcription.powerModeName = powerModeName
            transcription.powerModeEmoji = powerModeEmoji
            finalPastedText = text
            
            if let enhancementService = enhancementService, enhancementService.isConfigured {
                let detectionResult = await promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }

            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                if await checkCancellationAndCleanup() { return }

                await MainActor.run { self.recordingState = .enhancing }
                let textForAI = promptDetectionResult?.processedText ?? text
                
                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    logger.notice("📝 AI enhancement: \(enhancedText, privacy: .public)")
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    finalPastedText = enhancedText
                } catch {
                    transcription.enhancedText = "Enhancement failed: \(error)"
                  
                    if await checkCancellationAndCleanup() { return }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue

        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
            let fullErrorText = recoverySuggestion.isEmpty ? errorDescription : "\(errorDescription) \(recoverySuggestion)"

            transcription.text = "Transcription Failed: \(fullErrorText)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        // --- Finalize and save ---
        try? modelContext.save()
        
        if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
        }

        if await checkCancellationAndCleanup() { return }

        if var textToPaste = finalPastedText, transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            if isDosMode {
                // Save as Do with screen recording
                // Validate video file exists and has content
                var validVideoURL: String? = nil
                var thumbnailData: Data? = nil

                if let videoURL = recordedVideoFile {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
                    let fileSize = attributes?[.size] as? Int64 ?? 0
                    if fileSize > 0 {
                        validVideoURL = videoURL.absoluteString
                        thumbnailData = screenRecordingService.extractThumbnail(from: videoURL)
                        logger.info("✅ Video file validated: \(fileSize) bytes")
                    } else {
                        logger.warning("⚠️ Video file is empty or missing, not saving video URL")
                    }
                } else {
                    logger.warning("⚠️ No video file URL recorded")
                }

                let doItem = Do(
                    text: transcription.text,
                    duration: transcription.duration,
                    enhancedText: transcription.enhancedText,
                    videoFileURL: validVideoURL,
                    audioFileURL: transcription.audioFileURL,
                    thumbnailData: thumbnailData,
                    transcriptionModelName: transcription.transcriptionModelName,
                    aiEnhancementModelName: transcription.aiEnhancementModelName,
                    promptName: transcription.promptName,
                    transcriptionDuration: transcription.transcriptionDuration,
                    enhancementDuration: transcription.enhancementDuration,
                    videoDescriptionStatus: validVideoURL != nil ? VideoDescriptionStatus.pending.rawValue : nil
                )
                modelContext.insert(doItem)
                try? modelContext.save()

                // Delete the temporary Transcription object (we don't need it in history)
                modelContext.delete(transcription)
                try? modelContext.save()

                // Post notification for Dos UI to refresh
                NotificationCenter.default.post(name: .doCreated, object: doItem)

                // Trigger background video description generation
                if let videoURLString = validVideoURL, let videoURL = URL(string: videoURLString) {
                    let doId = doItem.id
                    Task.detached { [weak self] in
                        guard let self = self else { return }
                        await self.generateVideoDescription(forDoId: doId, videoURL: videoURL)
                    }
                }

                // Reset dos mode and video file
                isDosMode = false
                recordedVideoFile = nil

                // DO NOT paste to cursor - saved as Do
            } else if isNotesMode {
                // Save as Note instead of pasting to cursor
                let note = Note(
                    text: transcription.text,
                    duration: transcription.duration,
                    enhancedText: transcription.enhancedText,
                    audioFileURL: transcription.audioFileURL,
                    transcriptionModelName: transcription.transcriptionModelName,
                    aiEnhancementModelName: transcription.aiEnhancementModelName,
                    promptName: transcription.promptName,
                    transcriptionDuration: transcription.transcriptionDuration,
                    enhancementDuration: transcription.enhancementDuration
                )
                modelContext.insert(note)
                try? modelContext.save()

                // Delete the temporary Transcription object (we don't need it in history)
                modelContext.delete(transcription)
                try? modelContext.save()

                // Post notification for Notes UI to refresh
                NotificationCenter.default.post(name: .noteCreated, object: note)

                // Reset notes mode
                isNotesMode = false

                // DO NOT paste to cursor - just saved as note
            } else {
                // Original paste behavior
                if case .trialExpired = licenseViewModel.licenseState {
                    textToPaste = """
                        Your trial has expired. Upgrade to VoiceInk Beta at tryvoiceink.com/buy
                        \n\(textToPaste)
                        """
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    CursorPaster.pasteAtCursor(textToPaste + " ")

                    let powerMode = PowerModeManager.shared
                    if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.isAutoSendEnabled {
                        // Slight delay to ensure the paste operation completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            CursorPaster.pressEnter()
                        }
                    }
                }
            }
        }

        if let result = promptDetectionResult,
           let enhancementService = enhancementService,
           result.shouldEnableAI {
            await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
        }

        await self.dismissMiniRecorder()

        shouldCancelRecording = false
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    /// Start screen recording for Dos mode (called from HotkeyManager when Shift+tap-tap is detected)
    func startScreenRecordingForDosMode() async {
        // Wait for recording state to stabilize (audio recording starts async)
        var attempts = 0
        while recordingState != .recording && attempts < 10 {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            attempts += 1
        }

        guard recordingState == .recording else {
            logger.error("❌ Cannot start screen recording: audio not recording after waiting (\(attempts) attempts)")
            NotificationManager.shared.showNotification(
                title: "Screen recording failed - audio not ready",
                type: .error
            )
            return
        }

        do {
            recordedVideoFile = try await screenRecordingService.startRecording()
            logger.info("🎬 Screen recording started for Dos mode (waited \(attempts) attempts)")
        } catch {
            logger.error("❌ Failed to start screen recording: \(error.localizedDescription)")
            NotificationManager.shared.showNotification(
                title: "Screen recording failed",
                type: .error
            )
        }
    }
    
    private func checkCancellationAndCleanup() async -> Bool {
        if shouldCancelRecording {
            await cleanupModelResources()
            return true
        }
        return false
    }

    private func cleanupAndDismiss() async {
        await dismissMiniRecorder()
    }

    // MARK: - Video Description Generation

    private func generateVideoDescription(forDoId doId: UUID, videoURL: URL) async {
        logger.info("🎬 Starting video description generation for Do: \(doId)")

        // Fetch the Do object from the database
        let fetchDescriptor = FetchDescriptor<Do>(predicate: #Predicate { $0.id == doId })
        guard let doItem = try? modelContext.fetch(fetchDescriptor).first else {
            logger.error("❌ Could not find Do with id: \(doId)")
            return
        }

        // Update status to processing
        await MainActor.run {
            doItem.videoDescriptionStatus = VideoDescriptionStatus.processing.rawValue
            try? modelContext.save()
        }

        do {
            let result = try await VideoAnalysisService.shared.analyzeVideo(at: videoURL)

            await MainActor.run {
                doItem.videoDescription = result.description
                doItem.videoDescriptionStatus = VideoDescriptionStatus.completed.rawValue
                doItem.videoDescriptionModelName = result.modelName
                try? modelContext.save()

                NotificationCenter.default.post(name: .doDescriptionUpdated, object: doItem)
                logger.info("✅ Video description completed for Do: \(doId)")
            }
        } catch {
            await MainActor.run {
                doItem.videoDescriptionStatus = VideoDescriptionStatus.failed.rawValue
                doItem.videoDescriptionError = error.localizedDescription
                try? modelContext.save()

                NotificationCenter.default.post(name: .doDescriptionUpdated, object: doItem)
                logger.error("❌ Video description failed for Do: \(doId): \(error.localizedDescription)")
            }
        }
    }
}
