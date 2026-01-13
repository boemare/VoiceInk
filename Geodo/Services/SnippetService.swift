import Foundation
import SwiftData

/// Service for expanding voice snippets in transcriptions
/// Inspired by Wispr Flow's voice shortcuts feature
class SnippetService {
    static let shared = SnippetService()

    private init() {}

    /// Apply snippet expansions to the given text
    /// - Parameters:
    ///   - text: The transcription text to process
    ///   - context: The SwiftData model context
    /// - Returns: Text with trigger phrases replaced by their expansions
    func applySnippets(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let snippets = try? context.fetch(descriptor), !snippets.isEmpty else {
            return text
        }

        var modifiedText = text

        for snippet in snippets {
            let trigger = snippet.trigger
            let expansion = snippet.expansion

            // Use word boundaries for matching (case-insensitive)
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: trigger))\\b"

            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                let matchCount = regex.numberOfMatches(in: modifiedText, options: [], range: range)

                if matchCount > 0 {
                    modifiedText = regex.stringByReplacingMatches(
                        in: modifiedText,
                        options: [],
                        range: range,
                        withTemplate: expansion
                    )

                    // Update usage statistics
                    snippet.usageCount += matchCount
                    snippet.dateLastUsed = Date()
                }
            }
        }

        // Save usage updates
        try? context.save()

        return modifiedText
    }

    /// Get all snippets sorted by usage count (most used first)
    func getAllSnippets(from context: ModelContext) -> [Snippet] {
        let descriptor = FetchDescriptor<Snippet>(
            sortBy: [SortDescriptor(\.usageCount, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Check if a trigger phrase already exists
    func triggerExists(_ trigger: String, in context: ModelContext, excluding snippetId: UUID? = nil) -> Bool {
        let normalizedTrigger = trigger.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let descriptor = FetchDescriptor<Snippet>()
        guard let snippets = try? context.fetch(descriptor) else { return false }

        return snippets.contains { snippet in
            let existingTrigger = snippet.trigger.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let excludeId = snippetId, snippet.id == excludeId {
                return false
            }
            return existingTrigger == normalizedTrigger
        }
    }
}
