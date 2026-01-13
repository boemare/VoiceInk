import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import os

enum VideoAnalysisError: LocalizedError {
    case missingAPIKey
    case fileUploadFailed(String)
    case analysisTimeout
    case invalidResponse
    case videoNotFound
    case processingFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not configured"
        case .fileUploadFailed(let msg):
            return "Video upload failed: \(msg)"
        case .analysisTimeout:
            return "Video analysis timed out"
        case .invalidResponse:
            return "Invalid response from AI provider"
        case .videoNotFound:
            return "Video file not found"
        case .processingFailed(let msg):
            return "Processing failed: \(msg)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

enum VideoDescriptionStatus: String {
    case pending
    case processing
    case completed
    case failed
}

struct VideoAnalysisResult {
    let description: String
    let modelName: String
    let duration: TimeInterval
}

class VideoAnalysisService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VideoAnalysis")

    static let shared = VideoAnalysisService()

    private init() {}

    // MARK: - Main Analysis Entry Point

    func analyzeVideo(at url: URL) async throws -> VideoAnalysisResult {
        let startTime = Date()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoAnalysisError.videoNotFound
        }

        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Gemini"), !apiKey.isEmpty else {
            throw VideoAnalysisError.missingAPIKey
        }

        logger.notice("Starting video analysis for: \(url.lastPathComponent, privacy: .public)")

        // Get video duration to determine analysis strategy
        let videoDuration = try await getVideoDuration(url)
        logger.notice("Video duration: \(videoDuration, privacy: .public) seconds")

        let description: String

        if videoDuration > 120 {
            // Long video (>2 min): Extract frames at 0.25fps and send as images
            logger.notice("Using frame extraction mode for long video")
            let fps = 0.25
            let frames = try await extractFrames(from: url, fps: fps)
            logger.notice("Extracted \(frames.count, privacy: .public) frames")
            description = try await analyzeFrames(frames, apiKey: apiKey)
        } else if videoDuration > 30 {
            // Medium video (30s-2min): Extract frames at 0.5fps
            logger.notice("Using frame extraction mode for medium video")
            let fps = 0.5
            let frames = try await extractFrames(from: url, fps: fps)
            logger.notice("Extracted \(frames.count, privacy: .public) frames")
            description = try await analyzeFrames(frames, apiKey: apiKey)
        } else {
            // Short video (<30s): Upload full video with low resolution
            logger.notice("Using full video upload mode for short video")
            description = try await analyzeWithGemini(videoURL: url, apiKey: apiKey)
        }

        let processingDuration = Date().timeIntervalSince(startTime)
        logger.notice("Video analysis completed in \(processingDuration, privacy: .public) seconds")

        return VideoAnalysisResult(
            description: description,
            modelName: "gemini-1.5-flash", // Free tier: 15 RPM, 1M TPM - supports vision
            duration: processingDuration
        )
    }

    // MARK: - Video Duration

    private func getVideoDuration(_ url: URL) async throws -> Double {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    // MARK: - Frame Extraction

    private func extractFrames(from url: URL, fps: Double) async throws -> [CGImage] {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720) // Cap resolution for efficiency

        var frames: [CGImage] = []
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let interval = 1.0 / fps

        for second in stride(from: 0, to: durationSeconds, by: interval) {
            let time = CMTime(seconds: second, preferredTimescale: 600)
            do {
                let image = try generator.copyCGImage(at: time, actualTime: nil)
                frames.append(image)
            } catch {
                logger.warning("Failed to extract frame at \(second)s: \(error.localizedDescription)")
            }
        }

        return frames
    }

    // MARK: - Frame-based Analysis

    private func analyzeFrames(_ frames: [CGImage], apiKey: String) async throws -> String {
        let generateURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert frames to base64 JPEG images
        var parts: [GeminiGeneratePart] = []

        let prompt = """
        These are \(frames.count) frames extracted from a screen recording.
        Describe what is happening in this recording. Focus on:
        - The application or website being used
        - Actions being taken by the user
        - Key visual elements and UI interactions
        Be concise but comprehensive.
        """
        parts.append(GeminiGeneratePart(text: prompt, fileData: nil, inlineData: nil))

        // Add each frame as an inline image
        for frame in frames {
            if let jpegData = convertToJPEG(frame, quality: 0.6) {
                let base64 = jpegData.base64EncodedString()
                parts.append(GeminiGeneratePart(
                    text: nil,
                    fileData: nil,
                    inlineData: InlineData(mimeType: "image/jpeg", data: base64)
                ))
            }
        }

        let requestBody = GeminiGenerateRequest(
            contents: [GeminiGenerateContent(parts: parts)],
            generationConfig: nil
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        logger.notice("Gemini frames raw response: \(rawResponse.prefix(1000), privacy: .public)")

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            logger.error("Gemini frames failed (HTTP \(statusCode)): \(rawResponse, privacy: .public)")
            throw VideoAnalysisError.processingFailed("HTTP \(statusCode): \(rawResponse.prefix(500))")
        }

        let generateResponse: GeminiGenerateResponse
        do {
            generateResponse = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        } catch {
            logger.error("Failed to decode frames response: \(error.localizedDescription, privacy: .public)")
            throw VideoAnalysisError.processingFailed("Decode error: \(error.localizedDescription). Raw: \(rawResponse.prefix(300))")
        }

        guard let candidate = generateResponse.candidates.first,
              let part = candidate.content.parts.first,
              let text = part.text, !text.isEmpty else {
            logger.error("No valid text in frames response: \(rawResponse, privacy: .public)")
            throw VideoAnalysisError.processingFailed("No text in response: \(rawResponse.prefix(500))")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertToJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    // MARK: - Gemini Video Analysis

    private func analyzeWithGemini(videoURL: URL, apiKey: String) async throws -> String {
        // Step 1: Upload video to Gemini Files API
        let fileUri = try await uploadVideoToGemini(videoURL: videoURL, apiKey: apiKey)
        logger.notice("Video uploaded, file URI: \(fileUri, privacy: .public)")

        // Step 2: Wait for video processing
        try await waitForVideoProcessing(fileUri: fileUri, apiKey: apiKey)
        logger.notice("Video processing complete")

        // Step 3: Generate description
        let description = try await generateVideoDescription(fileUri: fileUri, apiKey: apiKey)
        return description
    }

    private func uploadVideoToGemini(videoURL: URL, apiKey: String) async throws -> String {
        let videoData = try Data(contentsOf: videoURL)
        let mimeType = "video/quicktime"
        let displayName = videoURL.lastPathComponent

        // Start resumable upload
        let startUploadURL = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files?key=\(apiKey)")!

        var startRequest = URLRequest(url: startUploadURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("\(videoData.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let metadata = ["file": ["display_name": displayName]]
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (_, startResponse) = try await URLSession.shared.data(for: startRequest)

        guard let httpResponse = startResponse as? HTTPURLResponse,
              let uploadUrl = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL") else {
            throw VideoAnalysisError.fileUploadFailed("Failed to get upload URL")
        }

        // Upload the actual video data
        var uploadRequest = URLRequest(url: URL(string: uploadUrl)!)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = videoData

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)

        guard let uploadHttpResponse = uploadResponse as? HTTPURLResponse,
              (200 ... 299).contains(uploadHttpResponse.statusCode) else {
            let errorMessage = String(data: uploadData, encoding: .utf8) ?? "Unknown error"
            throw VideoAnalysisError.fileUploadFailed(errorMessage)
        }

        // Parse file info from response
        let fileInfo = try JSONDecoder().decode(GeminiFileResponse.self, from: uploadData)
        return fileInfo.file.uri
    }

    private func waitForVideoProcessing(fileUri: String, apiKey: String) async throws {
        let fileName = fileUri.components(separatedBy: "/").last ?? ""
        let statusURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/files/\(fileName)?key=\(apiKey)")!

        let maxAttempts = 60 // 5 minutes max (5 seconds between attempts)
        var attempts = 0

        while attempts < maxAttempts {
            var request = URLRequest(url: statusURL)
            request.httpMethod = "GET"

            let (data, _) = try await URLSession.shared.data(for: request)
            let fileStatus = try JSONDecoder().decode(GeminiFileStatusResponse.self, from: data)

            if fileStatus.state == "ACTIVE" {
                return
            } else if fileStatus.state == "FAILED" {
                throw VideoAnalysisError.processingFailed("Gemini video processing failed")
            }

            // Wait 5 seconds before next check
            try await Task.sleep(nanoseconds: 5_000_000_000)
            attempts += 1
        }

        throw VideoAnalysisError.analysisTimeout
    }

    private func generateVideoDescription(fileUri: String, apiKey: String) async throws -> String {
        let generateURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Describe what is happening in this screen recording. Focus on:
        - The application or website being used
        - Actions being taken by the user
        - Key visual elements and UI interactions
        Be concise but comprehensive.
        """

        let requestBody = GeminiGenerateRequest(
            contents: [
                GeminiGenerateContent(
                    parts: [
                        GeminiGeneratePart(text: prompt, fileData: nil, inlineData: nil),
                        GeminiGeneratePart(text: nil, fileData: GeminiFileData(mimeType: "video/quicktime", fileUri: fileUri), inlineData: nil)
                    ]
                )
            ],
            generationConfig: nil // 75% token reduction
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        logger.notice("Gemini video raw response: \(rawResponse.prefix(1000), privacy: .public)")

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            logger.error("Gemini video failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)): \(rawResponse, privacy: .public)")
            throw VideoAnalysisError.processingFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(rawResponse.prefix(500))")
        }

        let generateResponse: GeminiGenerateResponse
        do {
            generateResponse = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        } catch {
            logger.error("Failed to decode video response: \(error.localizedDescription, privacy: .public)")
            throw VideoAnalysisError.processingFailed("Decode error: \(error.localizedDescription). Raw: \(rawResponse.prefix(300))")
        }

        guard let candidate = generateResponse.candidates.first,
              let part = candidate.content.parts.first,
              let text = part.text, !text.isEmpty else {
            logger.error("No valid text in video response: \(rawResponse, privacy: .public)")
            throw VideoAnalysisError.processingFailed("No text in response: \(rawResponse.prefix(500))")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Response Models

    private struct GeminiFileResponse: Codable {
        let file: GeminiFile
    }

    private struct GeminiFile: Codable {
        let name: String
        let uri: String
        let mimeType: String
        let state: String
    }

    private struct GeminiFileStatusResponse: Codable {
        let name: String
        let state: String
    }

    private struct GeminiGenerateRequest: Codable {
        let contents: [GeminiGenerateContent]
        let generationConfig: GenerationConfig?
    }

    private struct GenerationConfig: Codable {
        let mediaResolution: String

        enum CodingKeys: String, CodingKey {
            case mediaResolution = "media_resolution"
        }
    }

    private struct GeminiGenerateContent: Codable {
        let parts: [GeminiGeneratePart]
    }

    private struct GeminiGeneratePart: Codable {
        let text: String?
        let fileData: GeminiFileData?
        let inlineData: InlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case fileData = "file_data"
            case inlineData = "inline_data"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let text = text {
                try container.encode(text, forKey: .text)
            }
            if let fileData = fileData {
                try container.encode(fileData, forKey: .fileData)
            }
            if let inlineData = inlineData {
                try container.encode(inlineData, forKey: .inlineData)
            }
        }
    }

    private struct InlineData: Codable {
        let mimeType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }

    private struct GeminiFileData: Codable {
        let mimeType: String
        let fileUri: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case fileUri = "file_uri"
        }
    }

    private struct GeminiGenerateResponse: Codable {
        let candidates: [GeminiGenerateCandidate]
    }

    private struct GeminiGenerateCandidate: Codable {
        let content: GeminiGenerateResponseContent
    }

    private struct GeminiGenerateResponseContent: Codable {
        let parts: [GeminiGenerateResponsePart]
    }

    private struct GeminiGenerateResponsePart: Codable {
        let text: String?
    }
}
