import Foundation
import SwiftData

@Model
final class Do {
    var id: UUID
    var text: String
    var enhancedText: String?
    var timestamp: Date
    var duration: TimeInterval
    var videoFileURL: String?
    var audioFileURL: String?
    var thumbnailData: Data?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?

    init(text: String,
         duration: TimeInterval,
         enhancedText: String? = nil,
         videoFileURL: String? = nil,
         audioFileURL: String? = nil,
         thumbnailData: Data? = nil,
         transcriptionModelName: String? = nil,
         aiEnhancementModelName: String? = nil,
         promptName: String? = nil,
         transcriptionDuration: TimeInterval? = nil,
         enhancementDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.duration = duration
        self.videoFileURL = videoFileURL
        self.audioFileURL = audioFileURL
        self.thumbnailData = thumbnailData
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.promptName = promptName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
    }
}
