import SwiftUI
import SwiftData

struct MeetingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var meetingRecorder = MeetingRecorderService()
    @State private var searchText = ""
    @State private var selectedMeeting: Meeting?
    @State private var selectedMeetings: Set<Meeting> = []
    @State private var showDeleteConfirmation = false
    @State private var isViewCurrentlyVisible = false
    @State private var displayedMeetings: [Meeting] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?

    private let pageSize = 20

    @Query(Self.createLatestMeetingIndicatorDescriptor()) private var latestMeetingIndicator: [Meeting]

    private static func createLatestMeetingIndicatorDescriptor() -> FetchDescriptor<Meeting> {
        var descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Meeting> {
        var descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\Meeting.timestamp, order: .reverse)]
        )

        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Meeting> { meeting in
                    (meeting.text.localizedStandardContains(searchText) ||
                    (meeting.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    meeting.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Meeting> { meeting in
                    meeting.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Meeting> { meeting in
                meeting.text.localizedStandardContains(searchText) ||
                (meeting.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar with meetings list
            VStack(spacing: 0) {
                // Recording controls at top
                MeetingRecorderView(recorder: meetingRecorder) { result in
                    Task {
                        await handleRecordingComplete(result)
                    }
                }
                .padding(12)

                Divider()

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("Search meetings", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.thinMaterial)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                ZStack(alignment: .bottom) {
                    if displayedMeetings.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.wave.2")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No meetings yet")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Record a meeting to get started")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(displayedMeetings) { meeting in
                                    MeetingListItem(
                                        meeting: meeting,
                                        isSelected: selectedMeeting == meeting,
                                        isChecked: selectedMeetings.contains(meeting),
                                        onSelect: { selectedMeeting = meeting },
                                        onToggleCheck: { toggleSelection(meeting) }
                                    )
                                }

                                if hasMoreContent {
                                    Button(action: {
                                        Task { await loadMoreContent() }
                                    }) {
                                        HStack(spacing: 8) {
                                            if isLoading {
                                                ProgressView().controlSize(.small)
                                            }
                                            Text(isLoading ? "Loading..." : "Load More")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isLoading)
                                }
                            }
                            .padding(8)
                            .padding(.bottom, !selectedMeetings.isEmpty ? 50 : 0)
                        }
                    }

                    if !selectedMeetings.isEmpty {
                        selectionToolbar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: 300)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Center pane with meeting detail
            Group {
                if let meeting = selectedMeeting {
                    MeetingDetailView(meeting: meeting)
                        .id(meeting.id)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.wave.2")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No Selection")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Select a meeting to view details")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .alert("Delete Selected Meetings?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedMeetings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete \(selectedMeetings.count) meeting\(selectedMeetings.count == 1 ? "" : "s")?")
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task {
                await loadInitialContent()
            }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in
            Task {
                await resetPagination()
                await loadInitialContent()
            }
        }
        .onChange(of: latestMeetingIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                }
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { copySelectedMeetings() }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy")

            Button(action: { showDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete")

            Spacer()

            Text("\(selectedMeetings.count) selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.windowBackgroundColor)
                .shadow(color: Color.black.opacity(0.15), radius: 3, y: -2)
        )
    }

    private func handleRecordingComplete(_ result: MeetingRecordingResult) async {
        // Create a new meeting from the recording result
        // For now, create with placeholder text - transcription will be added later
        let meeting = Meeting(
            text: "Recording in progress...",
            duration: result.duration,
            mixedAudioFileURL: result.mixedAudioURL?.absoluteString,
            micAudioFileURL: result.micAudioURL?.absoluteString,
            systemAudioFileURL: result.systemAudioURL?.absoluteString
        )

        modelContext.insert(meeting)

        do {
            try modelContext.save()
            await loadInitialContent()
            selectedMeeting = meeting
        } catch {
            print("Error saving meeting: \(error)")
        }
    }

    @MainActor
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lastTimestamp = nil
            let items = try modelContext.fetch(cursorQueryDescriptor())
            displayedMeetings = items
            lastTimestamp = items.last?.timestamp
            hasMoreContent = items.count == pageSize
        } catch {
            print("Error loading meetings: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newItems = try modelContext.fetch(cursorQueryDescriptor(after: lastTimestamp))
            displayedMeetings.append(contentsOf: newItems)
            self.lastTimestamp = newItems.last?.timestamp
            hasMoreContent = newItems.count == pageSize
        } catch {
            print("Error loading more meetings: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedMeetings = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    private func performDeletion(for meeting: Meeting) {
        // Delete audio files
        for urlString in [meeting.mixedAudioFileURL, meeting.micAudioFileURL, meeting.systemAudioFileURL] {
            if let str = urlString,
               let url = URL(string: str),
               FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        if selectedMeeting == meeting {
            selectedMeeting = nil
        }

        selectedMeetings.remove(meeting)
        modelContext.delete(meeting)
    }

    private func saveAndReload() async {
        do {
            try modelContext.save()
            await loadInitialContent()
        } catch {
            print("Error saving deletion: \(error.localizedDescription)")
            await loadInitialContent()
        }
    }

    private func deleteSelectedMeetings() {
        for meeting in selectedMeetings {
            performDeletion(for: meeting)
        }
        selectedMeetings.removeAll()

        Task {
            await saveAndReload()
        }
    }

    private func toggleSelection(_ meeting: Meeting) {
        if selectedMeetings.contains(meeting) {
            selectedMeetings.remove(meeting)
        } else {
            selectedMeetings.insert(meeting)
        }
    }

    private func copySelectedMeetings() {
        let meetingsText = selectedMeetings
            .sorted { $0.timestamp > $1.timestamp }
            .map { $0.enhancedText ?? $0.text }
            .joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(meetingsText, forType: .string)
    }
}
