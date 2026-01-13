import Foundation
import SwiftData

/// Voice snippet that expands a trigger phrase into full text
/// Inspired by Wispr Flow's voice shortcuts feature
@Model
final class Snippet {
    var id: UUID
    var trigger: String           // e.g., "my email"
    var expansion: String         // e.g., "john@example.com"
    var isEnabled: Bool
    var usageCount: Int
    var dateCreated: Date
    var dateLastUsed: Date?

    init(
        trigger: String,
        expansion: String,
        isEnabled: Bool = true,
        usageCount: Int = 0,
        dateCreated: Date = Date(),
        dateLastUsed: Date? = nil
    ) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.isEnabled = isEnabled
        self.usageCount = usageCount
        self.dateCreated = dateCreated
        self.dateLastUsed = dateLastUsed
    }
}
