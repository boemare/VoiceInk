import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var title: String?
    var text: String
    var enhancedText: String?
    var timestamp: Date
    var endTime: Date?
    var duration: TimeInterval
    var mixedAudioFileURL: String?
    var micAudioFileURL: String?
    var systemAudioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var participants: [String]?
    var sourceApp: String?

    init(text: String,
         duration: TimeInterval,
         title: String? = nil,
         enhancedText: String? = nil,
         endTime: Date? = nil,
         mixedAudioFileURL: String? = nil,
         micAudioFileURL: String? = nil,
         systemAudioFileURL: String? = nil,
         transcriptionModelName: String? = nil,
         aiEnhancementModelName: String? = nil,
         promptName: String? = nil,
         transcriptionDuration: TimeInterval? = nil,
         enhancementDuration: TimeInterval? = nil,
         participants: [String]? = nil,
         sourceApp: String? = nil) {
        self.id = UUID()
        self.title = title
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.endTime = endTime
        self.duration = duration
        self.mixedAudioFileURL = mixedAudioFileURL
        self.micAudioFileURL = micAudioFileURL
        self.systemAudioFileURL = systemAudioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.promptName = promptName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.participants = participants
        self.sourceApp = sourceApp
    }
}
