import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @State private var viewMode: ViewMode = .transcript
    @State private var showSpeakerEditor = false
    @State private var isEnhancing = false
    @State private var showEnhancementError = false
    @State private var enhancementErrorMessage = ""

    enum ViewMode: String, CaseIterable {
        case transcript   // Plain text bubbles (Original/Enhanced)
        case conversation // Speaker-labeled conversation
        case insights     // AI-generated summary, action items, key points
    }

    private var hasAudioFile: Bool {
        if let urlString = note.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    private var hasEnhancement: Bool {
        note.summary != nil || note.actionItems != nil || note.keyPoints != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            headerView

            Divider()
                .padding(.horizontal, 16)

            // Content area
            contentView

            // Audio player
            if hasAudioFile, let urlString = note.audioFileURL,
               let url = URL(string: urlString) {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }

            // Metadata footer
            footerView
        }
        .background(Color(NSColor.controlBackgroundColor))
        .alert("Enhancement Error", isPresented: $showEnhancementError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(enhancementErrorMessage)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(note.isMeeting ? "Meeting" : "Note")
                        .font(.system(size: 18, weight: .semibold))

                    // Meeting badge with source app
                    if note.isMeeting, let sourceApp = note.sourceApp {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text(sourceApp)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                    }

                    // Enhancement status badge
                    if note.enhancementStatus == "processing" || isEnhancing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Enhancing...")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.orange.opacity(0.15))
                        )
                    }
                }
                Text(note.timestamp, format: .dateTime.month(.wide).day().year().hour().minute())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()

            // View mode picker
            viewModePicker

            // Enhance menu button
            enhanceMenuButton

            // Export menu button
            exportMenuButton

            // Copy button
            Button(action: {
                let textToCopy = note.enhancedText ?? note.text
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(textToCopy, forType: .string)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            Image(systemName: "doc.text")
                .tag(ViewMode.transcript)
            if note.hasDiarization {
                Image(systemName: "bubble.left.and.bubble.right")
                    .tag(ViewMode.conversation)
            }
            if hasEnhancement {
                Image(systemName: "sparkles")
                    .tag(ViewMode.insights)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: hasEnhancement ? (note.hasDiarization ? 105 : 70) : (note.hasDiarization ? 70 : 0))
        .help("Switch view mode")
    }

    private var enhanceMenuButton: some View {
        Menu {
            Button(action: { enhanceNote(style: .full) }) {
                Label("Full Enhancement", systemImage: "sparkles")
            }

            Divider()

            Button(action: { enhanceNote(style: .summaryOnly) }) {
                Label("Summary Only", systemImage: "text.alignleft")
            }

            Button(action: { enhanceNote(style: .actionItemsOnly) }) {
                Label("Action Items Only", systemImage: "checklist")
            }

            Button(action: { enhanceNote(style: .keyPointsOnly) }) {
                Label("Key Points Only", systemImage: "list.bullet")
            }

            if hasEnhancement {
                Divider()

                Button(role: .destructive, action: clearEnhancement) {
                    Label("Clear Enhancement", systemImage: "trash")
                }
            }
        } label: {
            Label("Enhance", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 90)
        .disabled(isEnhancing)
    }

    private var exportMenuButton: some View {
        Menu {
            Button(action: { exportMarkdown() }) {
                Label("Export as Markdown", systemImage: "doc.text")
            }

            Button(action: { exportPDF() }) {
                Label("Export as PDF", systemImage: "doc.richtext")
            }

            Divider()

            Button(action: { copyForObsidian() }) {
                Label("Copy for Obsidian", systemImage: "link")
            }

            Button(action: { shareNote() }) {
                Label("Share...", systemImage: "square.and.arrow.up")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 80)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .conversation:
            if note.hasDiarization, let segments = note.conversationSegments {
                ConversationView(
                    segments: segments,
                    speakerMap: note.speakerMap
                )
            } else {
                transcriptView
            }
        case .insights:
            insightsView
        case .transcript:
            transcriptView
        }
    }

    private var transcriptView: some View {
        ScrollView {
            VStack(spacing: 16) {
                NoteBubble(
                    label: "Original",
                    text: note.text,
                    isEnhanced: false
                )

                if let enhancedText = note.enhancedText {
                    NoteBubble(
                        label: "Enhanced",
                        text: enhancedText,
                        isEnhanced: true
                    )
                }
            }
            .padding(16)
        }
    }

    private var insightsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary section
                if let summary = note.summary {
                    InsightSection(
                        title: "Summary",
                        icon: "text.alignleft",
                        color: .blue
                    ) {
                        Text(summary)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }

                // Action Items section
                if let actionItems = note.actionItems, !actionItems.isEmpty {
                    InsightSection(
                        title: "Action Items",
                        icon: "checklist",
                        color: .green
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(actionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                    Text(item)
                                        .font(.system(size: 14))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                // Key Points section
                if let keyPoints = note.keyPoints, !keyPoints.isEmpty {
                    InsightSection(
                        title: "Key Points",
                        icon: "list.bullet",
                        color: .purple
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(.purple)
                                        .padding(.top, 6)
                                    Text(point)
                                        .font(.system(size: 14))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                // Empty state
                if !hasEnhancement {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No AI Insights Yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Use the Enhance button to generate summary, action items, and key points")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 16) {
            if note.duration > 0 {
                Label(note.duration.formatTiming(), systemImage: "waveform")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let modelName = note.transcriptionModelName {
                Label(modelName, systemImage: "cpu")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Show participants count for meetings
            if note.isMeeting, let participants = note.participants, !participants.isEmpty {
                Label("\(participants.count)", systemImage: "person.2")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func enhanceNote(style: NoteEnhancementStyle) {
        guard !isEnhancing else { return }

        isEnhancing = true

        Task {
            do {
                let aiService = AIService()
                let enhancementService = NoteEnhancementService(aiService: aiService, modelContext: modelContext)
                try await enhancementService.enhanceNote(note, style: style)

                await MainActor.run {
                    isEnhancing = false
                    // Switch to insights view if we have new content
                    if hasEnhancement && viewMode == .transcript {
                        viewMode = .insights
                    }
                }
            } catch {
                await MainActor.run {
                    isEnhancing = false
                    enhancementErrorMessage = error.localizedDescription
                    showEnhancementError = true
                }
            }
        }
    }

    private func clearEnhancement() {
        note.summary = nil
        note.actionItems = nil
        note.keyPoints = nil
        note.enhancementStatus = nil
        note.enhancementError = nil
        try? modelContext.save()

        if viewMode == .insights {
            viewMode = .transcript
        }
    }

    // MARK: - Export Actions

    private func exportMarkdown() {
        let exportService = NoteExportService()
        exportService.saveMarkdown(note: note)
    }

    private func exportPDF() {
        let exportService = NoteExportService()
        exportService.exportToPDF(note: note)
    }

    private func copyForObsidian() {
        let exportService = NoteExportService()
        exportService.copyForObsidian(note: note)
    }

    private func shareNote() {
        // For share, we need a view reference. Use a simple approach with pasteboard + notification.
        let exportService = NoteExportService()
        let content = exportService.exportToMarkdown(note: note)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        // Show a brief notification that content was copied for sharing
        // In a full implementation, you'd use the share sheet with proper view reference
    }
}

// MARK: - Supporting Views

private struct InsightSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }

            content
                .padding(.leading, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(color.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

private struct NoteBubble: View {
    let label: String
    let text: String
    let isEnhanced: Bool
    @State private var justCopied = false

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 12)

                ScrollView {
                    Text(text)
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
                .background {
                    if isEnhanced {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.cream.opacity(0.06), lineWidth: 0.5)
                            )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: {
                        copyToClipboard(text)
                    }) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(justCopied ? .green : .secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                    .padding(8)
                }
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            justCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                justCopied = false
            }
        }
    }
}
