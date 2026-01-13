import Foundation

/// Service for removing filler words (um, uh, like, etc.) from transcriptions
/// Inspired by Wispr Flow's automatic filler word removal feature
final class FillerWordFilterService {
    static let shared = FillerWordFilterService()

    /// Default filler words to remove
    private let defaultFillerWords: [String] = [
        // Common hesitation sounds
        "um", "umm", "uh", "uhh", "er", "err", "ah", "ahh",
        // Filler phrases
        "you know", "i mean", "sort of", "kind of",
        // Repeated words often used as fillers
        "like", "basically", "literally", "actually",
        // Self-correction phrases (will be handled specially)
        "well", "so"
    ]

    /// Phrases that indicate self-correction - the preceding clause should be removed
    private let selfCorrectionPhrases: [String] = [
        "no wait", "no, wait", "actually no", "sorry,", "i meant", "i mean,",
        "let me rephrase", "what i meant was", "correction:"
    ]

    private init() {
        // Set default value if not already set
        if UserDefaults.standard.object(forKey: "isFillerWordRemovalEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "isFillerWordRemovalEnabled")
        }
    }

    /// Whether filler word removal is enabled
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isFillerWordRemovalEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "isFillerWordRemovalEnabled") }
    }

    /// Remove filler words from the given text
    /// - Parameter text: The transcription text to filter
    /// - Returns: Text with filler words removed
    func removeFillerWords(from text: String) -> String {
        guard isEnabled else { return text }
        guard !text.isEmpty else { return text }

        var result = text

        // First, handle multi-word filler phrases (case-insensitive)
        let multiWordFillers = ["you know", "i mean", "sort of", "kind of"]
        for filler in multiWordFillers {
            result = removePhrase(filler, from: result)
        }

        // Then handle single-word fillers with word boundaries
        let singleWordFillers = ["um", "umm", "uh", "uhh", "er", "err", "ah", "ahh", "like", "basically", "literally"]
        for filler in singleWordFillers {
            result = removeWord(filler, from: result)
        }

        // Clean up resulting text
        result = cleanupText(result)

        return result
    }

    /// Remove a single word filler using word boundaries
    private func removeWord(_ word: String, from text: String) -> String {
        // Pattern matches the word with optional surrounding punctuation/spaces
        // Handles cases like "um," or "um." or "um "
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b[,.]?\\s*"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// Remove a multi-word phrase from text
    private func removePhrase(_ phrase: String, from text: String) -> String {
        // Pattern matches the phrase with optional trailing punctuation
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b[,.]?\\s*"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// Clean up text after filler removal
    private func cleanupText(_ text: String) -> String {
        var result = text

        // Remove multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Remove space before punctuation
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " !", with: "!")
        result = result.replacingOccurrences(of: " ?", with: "?")

        // Remove leading/trailing punctuation that might be orphaned
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fix sentences that now start with lowercase after filler removal
        result = capitalizeAfterPunctuation(result)

        return result
    }

    /// Capitalize letters after sentence-ending punctuation
    private func capitalizeAfterPunctuation(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
                if char == "." || char == "!" || char == "?" {
                    capitalizeNext = true
                } else if !char.isWhitespace {
                    capitalizeNext = false
                }
            }
        }

        return result
    }
}

// MARK: - UserDefaults Extension
extension UserDefaults {
    var isFillerWordRemovalEnabled: Bool {
        get { bool(forKey: "isFillerWordRemovalEnabled") }
        set { set(newValue, forKey: "isFillerWordRemovalEnabled") }
    }
}
