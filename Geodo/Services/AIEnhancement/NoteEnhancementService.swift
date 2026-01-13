import Foundation
import SwiftData
import os

/// Enhancement style options
enum NoteEnhancementStyle {
    case full           // Summary + action items + key points
    case summaryOnly
    case actionItemsOnly
    case keyPointsOnly
}

/// Response structure for full enhancement
struct FullEnhancementResponse: Codable {
    let summary: String
    let actionItems: [String]
    let keyPoints: [String]
}

/// Service for AI-powered note enhancement (hyprnote-style features)
@MainActor
class NoteEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NoteEnhancementService")
    private let aiService: AIService
    private let modelContext: ModelContext
    private let baseTimeout: TimeInterval = 60

    init(aiService: AIService, modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
    }

    /// Check if enhancement is available
    var isAvailable: Bool {
        aiService.isAPIKeyValid
    }

    /// Enhance a note with the specified style
    func enhanceNote(_ note: Note, style: NoteEnhancementStyle = .full) async throws {
        guard isAvailable else {
            throw NoteEnhancementError.notConfigured
        }

        let transcript = note.enhancedText ?? note.text
        guard !transcript.isEmpty else {
            throw NoteEnhancementError.emptyTranscript
        }

        // Update status to processing
        note.enhancementStatus = "processing"
        note.enhancementError = nil
        try? modelContext.save()

        do {
            switch style {
            case .full:
                try await performFullEnhancement(note: note, transcript: transcript)
            case .summaryOnly:
                try await performSummaryEnhancement(note: note, transcript: transcript)
            case .actionItemsOnly:
                try await performActionItemsEnhancement(note: note, transcript: transcript)
            case .keyPointsOnly:
                try await performKeyPointsEnhancement(note: note, transcript: transcript)
            }

            note.enhancementStatus = "completed"
            try? modelContext.save()
            NotificationCenter.default.post(name: .noteUpdated, object: nil)
            logger.notice("Note enhancement completed successfully")

        } catch {
            note.enhancementStatus = "failed"
            note.enhancementError = error.localizedDescription
            try? modelContext.save()
            NotificationCenter.default.post(name: .noteUpdated, object: nil)
            throw error
        }
    }

    // MARK: - Private Enhancement Methods

    private func performFullEnhancement(note: Note, transcript: String) async throws {
        let response = try await makeRequest(
            transcript: transcript,
            systemPrompt: MeetingEnhancementPrompts.fullEnhancementPrompt
        )

        // Parse JSON response
        guard let jsonData = response.data(using: .utf8) else {
            throw NoteEnhancementError.invalidResponse
        }

        do {
            let enhancement = try JSONDecoder().decode(FullEnhancementResponse.self, from: jsonData)
            note.summary = enhancement.summary
            note.actionItems = enhancement.actionItems.isEmpty ? nil : enhancement.actionItems
            note.keyPoints = enhancement.keyPoints.isEmpty ? nil : enhancement.keyPoints
        } catch {
            // Try to extract JSON from response (LLM might include extra text)
            if let extracted = extractJSON(from: response) {
                let enhancement = try JSONDecoder().decode(FullEnhancementResponse.self, from: extracted)
                note.summary = enhancement.summary
                note.actionItems = enhancement.actionItems.isEmpty ? nil : enhancement.actionItems
                note.keyPoints = enhancement.keyPoints.isEmpty ? nil : enhancement.keyPoints
            } else {
                logger.error("Failed to parse enhancement JSON: \(error.localizedDescription)")
                throw NoteEnhancementError.invalidResponse
            }
        }
    }

    private func performSummaryEnhancement(note: Note, transcript: String) async throws {
        let response = try await makeRequest(
            transcript: transcript,
            systemPrompt: MeetingEnhancementPrompts.summaryPrompt
        )
        note.summary = response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performActionItemsEnhancement(note: Note, transcript: String) async throws {
        let response = try await makeRequest(
            transcript: transcript,
            systemPrompt: MeetingEnhancementPrompts.actionItemsPrompt
        )

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "NONE" || trimmed.isEmpty {
            note.actionItems = nil
        } else {
            let items = trimmed
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { line -> String in
                    // Remove leading bullet points or dashes
                    var cleaned = line
                    if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
                    if cleaned.hasPrefix("• ") { cleaned = String(cleaned.dropFirst(2)) }
                    if cleaned.hasPrefix("* ") { cleaned = String(cleaned.dropFirst(2)) }
                    // Remove leading numbers like "1. "
                    if let range = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                        cleaned = String(cleaned[range.upperBound...])
                    }
                    return cleaned
                }
                .filter { !$0.isEmpty }

            note.actionItems = items.isEmpty ? nil : items
        }
    }

    private func performKeyPointsEnhancement(note: Note, transcript: String) async throws {
        let response = try await makeRequest(
            transcript: transcript,
            systemPrompt: MeetingEnhancementPrompts.keyPointsPrompt
        )

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "NONE" || trimmed.isEmpty {
            note.keyPoints = nil
        } else {
            let points = trimmed
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { line -> String in
                    // Remove leading bullet points or dashes
                    var cleaned = line
                    if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
                    if cleaned.hasPrefix("• ") { cleaned = String(cleaned.dropFirst(2)) }
                    if cleaned.hasPrefix("* ") { cleaned = String(cleaned.dropFirst(2)) }
                    // Remove leading numbers like "1. "
                    if let range = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                        cleaned = String(cleaned[range.upperBound...])
                    }
                    return cleaned
                }
                .filter { !$0.isEmpty }

            note.keyPoints = points.isEmpty ? nil : points
        }
    }

    // MARK: - API Request

    private func makeRequest(transcript: String, systemPrompt: String) async throws -> String {
        let formattedTranscript = "<TRANSCRIPT>\n\(transcript)\n</TRANSCRIPT>"

        if aiService.selectedProvider == .ollama {
            return try await aiService.enhanceWithOllama(text: formattedTranscript, systemPrompt: systemPrompt)
        }

        switch aiService.selectedProvider {
        case .anthropic:
            return try await makeAnthropicRequest(transcript: formattedTranscript, systemPrompt: systemPrompt)
        default:
            return try await makeOpenAICompatibleRequest(transcript: formattedTranscript, systemPrompt: systemPrompt)
        }
    }

    private func makeAnthropicRequest(transcript: String, systemPrompt: String) async throws -> String {
        let requestBody: [String: Any] = [
            "model": aiService.currentModel,
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": transcript]
            ]
        ]

        var request = URLRequest(url: URL(string: aiService.selectedProvider.baseURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(aiService.apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = baseTimeout
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NoteEnhancementError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NoteEnhancementError.apiError("HTTP \(httpResponse.statusCode): \(errorString)")
        }

        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = jsonResponse["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw NoteEnhancementError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeOpenAICompatibleRequest(transcript: String, systemPrompt: String) async throws -> String {
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": transcript]
        ]

        let requestBody: [String: Any] = [
            "model": aiService.currentModel,
            "messages": messages,
            "temperature": 0.3,
            "stream": false
        ]

        var request = URLRequest(url: URL(string: aiService.selectedProvider.baseURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(aiService.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = baseTimeout
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NoteEnhancementError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NoteEnhancementError.apiError("HTTP \(httpResponse.statusCode): \(errorString)")
        }

        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonResponse["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw NoteEnhancementError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func extractJSON(from text: String) -> Data? {
        // Try to find JSON object in the response
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        let jsonString = String(text[start...end])
        return jsonString.data(using: .utf8)
    }

    /// Clear enhancement data from a note
    func clearEnhancement(_ note: Note) {
        note.summary = nil
        note.actionItems = nil
        note.keyPoints = nil
        note.enhancementStatus = nil
        note.enhancementError = nil
        try? modelContext.save()
        NotificationCenter.default.post(name: .noteUpdated, object: nil)
    }
}

// MARK: - Errors

enum NoteEnhancementError: Error {
    case notConfigured
    case emptyTranscript
    case invalidResponse
    case apiError(String)
}

extension NoteEnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please set up an API key in Settings."
        case .emptyTranscript:
            return "Cannot enhance an empty transcript."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .apiError(let message):
            return message
        }
    }
}
