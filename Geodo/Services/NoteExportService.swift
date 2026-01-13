import Foundation
import AppKit
import UniformTypeIdentifiers

/// Service for exporting notes to various formats
class NoteExportService {

    // MARK: - Markdown Export

    /// Generate markdown content for a note
    func exportToMarkdown(note: Note) -> String {
        var md = ""

        // YAML frontmatter
        md += "---\n"
        md += "title: \(note.isMeeting ? "Meeting" : "Note")\n"
        md += "date: \(ISO8601DateFormatter().string(from: note.timestamp))\n"
        md += "duration: \(note.duration.formatTiming())\n"

        if note.isMeeting, let sourceApp = note.sourceApp {
            md += "source_app: \(sourceApp)\n"
        }

        md += "type: \(note.isMeeting ? "meeting" : "note")\n"

        if let modelName = note.transcriptionModelName {
            md += "transcription_model: \(modelName)\n"
        }

        if note.hasDiarization {
            md += "has_diarization: true\n"
        }

        md += "---\n\n"

        // Summary section
        if let summary = note.summary {
            md += "## Summary\n\n"
            md += summary + "\n\n"
        }

        // Action Items section
        if let actionItems = note.actionItems, !actionItems.isEmpty {
            md += "## Action Items\n\n"
            for item in actionItems {
                md += "- [ ] \(item)\n"
            }
            md += "\n"
        }

        // Key Points section
        if let keyPoints = note.keyPoints, !keyPoints.isEmpty {
            md += "## Key Points\n\n"
            for point in keyPoints {
                md += "- \(point)\n"
            }
            md += "\n"
        }

        // Transcript section
        md += "## Transcript\n\n"
        if let enhancedText = note.enhancedText {
            md += enhancedText + "\n\n"
        } else {
            md += note.text + "\n\n"
        }

        // Conversation section (if diarized)
        if note.hasDiarization, let segments = note.conversationSegments {
            md += "## Conversation\n\n"
            let speakerMap = note.speakerMap ?? [:]

            for segment in segments {
                let speakerLabel = speakerMap[segment.speakerId] ?? segment.speakerLabel ?? segment.speakerId
                let timestamp = formatTimestamp(segment.startTime)
                md += "**\(speakerLabel)** (\(timestamp)): \(segment.text)\n\n"
            }
        }

        return md
    }

    /// Save markdown to file via NSSavePanel
    func saveMarkdown(note: Note) {
        let content = exportToMarkdown(note: note)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let defaultName = "\(note.isMeeting ? "Meeting" : "Note")_\(dateFormatter.string(from: note.timestamp)).md"

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "md")!]
        savePanel.nameFieldStringValue = defaultName
        savePanel.title = "Export as Markdown"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                showError("Failed to save markdown: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - PDF Export

    /// Export note as PDF via print dialog
    func exportToPDF(note: Note) {
        let content = exportToMarkdown(note: note)

        // Create attributed string for printing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraphStyle
        ]

        let attributedContent = NSAttributedString(string: content, attributes: attributes)

        // Create text view for printing
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612 - 72, height: 792 - 72))
        textView.textStorage?.setAttributedString(attributedContent)

        // Create print operation
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36

        let printOperation = NSPrintOperation(view: textView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.run()
    }

    // MARK: - Obsidian Export

    /// Generate markdown optimized for Obsidian
    func exportForObsidian(note: Note) -> String {
        var md = exportToMarkdown(note: note)

        // Add Obsidian-style daily note link
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: note.timestamp)
        let dailyLink = "[[Daily/\(dateString)]]"

        // Insert daily link after frontmatter
        if let range = md.range(of: "---\n\n") {
            md.insert(contentsOf: "Daily: \(dailyLink)\n\n", at: range.upperBound)
        }

        // Add tags
        var tags = ["#voice-note"]
        if note.isMeeting {
            tags.append("#meeting")
        }
        if note.hasDiarization {
            tags.append("#diarized")
        }
        if note.summary != nil {
            tags.append("#enhanced")
        }

        md += "\n---\n"
        md += "Tags: \(tags.joined(separator: " "))\n"

        return md
    }

    /// Copy Obsidian-formatted markdown to clipboard
    func copyForObsidian(note: Note) {
        let content = exportForObsidian(note: note)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    // MARK: - Share Sheet

    /// Show system share sheet
    func shareNote(note: Note, from view: NSView) {
        let content = exportToMarkdown(note: note)

        // Create temporary file for sharing
        let tempDir = FileManager.default.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "\(note.isMeeting ? "Meeting" : "Note")_\(dateFormatter.string(from: note.timestamp)).md"
        let tempURL = tempDir.appendingPathComponent(fileName)

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            showError("Failed to create temporary file: \(error.localizedDescription)")
            return
        }

        let picker = NSSharingServicePicker(items: [tempURL])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Share note with text content
    func shareNoteAsText(note: Note, from view: NSView) {
        let content = note.enhancedText ?? note.text
        let picker = NSSharingServicePicker(items: [content])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Export Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
