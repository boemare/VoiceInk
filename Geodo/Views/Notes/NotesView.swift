import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedNote: Note?
    @State private var selectedNotes: Set<Note> = []
    @State private var showDeleteConfirmation = false
    @State private var isViewCurrentlyVisible = false
    @State private var displayedNotes: [Note] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?

    private let pageSize = 20

    @Query(Self.createLatestNoteIndicatorDescriptor()) private var latestNoteIndicator: [Note]

    private static func createLatestNoteIndicatorDescriptor() -> FetchDescriptor<Note> {
        var descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Note> {
        var descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\Note.timestamp, order: .reverse)]
        )

        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Note> { note in
                    (note.text.localizedStandardContains(searchText) ||
                    (note.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    note.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Note> { note in
                    note.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Note> { note in
                note.text.localizedStandardContains(searchText) ||
                (note.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar with notes list
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("Search notes", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.thinMaterial)
                )
                .padding(12)

                Divider()

                ZStack(alignment: .bottom) {
                    if displayedNotes.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "note.text")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No notes yet")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Use tap-tap recording to save notes")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(displayedNotes) { note in
                                    NoteListItem(
                                        note: note,
                                        isSelected: selectedNote == note,
                                        isChecked: selectedNotes.contains(note),
                                        onSelect: { selectedNote = note },
                                        onToggleCheck: { toggleSelection(note) }
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
                            .padding(.bottom, !selectedNotes.isEmpty ? 50 : 0)
                        }
                    }

                    if !selectedNotes.isEmpty {
                        selectionToolbar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: 280)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Center pane with note detail
            Group {
                if let note = selectedNote {
                    NoteDetailView(note: note)
                        .id(note.id)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No Selection")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Select a note to view details")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .alert("Delete Selected Notes?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedNotes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete \(selectedNotes.count) note\(selectedNotes.count == 1 ? "" : "s")?")
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
        .onChange(of: latestNoteIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteCreated)) { _ in
            guard isViewCurrentlyVisible else { return }
            Task {
                await resetPagination()
                await loadInitialContent()
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { copySelectedNotes() }) {
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

            Text("\(selectedNotes.count) selected")
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

    @MainActor
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lastTimestamp = nil
            let items = try modelContext.fetch(cursorQueryDescriptor())
            displayedNotes = items
            lastTimestamp = items.last?.timestamp
            hasMoreContent = items.count == pageSize
        } catch {
            print("Error loading notes: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newItems = try modelContext.fetch(cursorQueryDescriptor(after: lastTimestamp))
            displayedNotes.append(contentsOf: newItems)
            self.lastTimestamp = newItems.last?.timestamp
            hasMoreContent = newItems.count == pageSize
        } catch {
            print("Error loading more notes: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedNotes = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    private func performDeletion(for note: Note) {
        if let urlString = note.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        if selectedNote == note {
            selectedNote = nil
        }

        selectedNotes.remove(note)
        modelContext.delete(note)
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

    private func deleteSelectedNotes() {
        for note in selectedNotes {
            performDeletion(for: note)
        }
        selectedNotes.removeAll()

        Task {
            await saveAndReload()
        }
    }

    private func toggleSelection(_ note: Note) {
        if selectedNotes.contains(note) {
            selectedNotes.remove(note)
        } else {
            selectedNotes.insert(note)
        }
    }

    private func copySelectedNotes() {
        let notesText = selectedNotes
            .sorted { $0.timestamp > $1.timestamp }
            .map { $0.enhancedText ?? $0.text }
            .joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notesText, forType: .string)
    }
}
