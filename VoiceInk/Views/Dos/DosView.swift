import SwiftUI
import SwiftData

struct DosView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedDo: Do?
    @State private var selectedDos: Set<Do> = []
    @State private var showDeleteConfirmation = false
    @State private var isViewCurrentlyVisible = false
    @State private var displayedDos: [Do] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?

    private let pageSize = 20

    @Query(Self.createLatestDoIndicatorDescriptor()) private var latestDoIndicator: [Do]

    private static func createLatestDoIndicatorDescriptor() -> FetchDescriptor<Do> {
        var descriptor = FetchDescriptor<Do>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Do> {
        var descriptor = FetchDescriptor<Do>(
            sortBy: [SortDescriptor(\Do.timestamp, order: .reverse)]
        )

        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Do> { doItem in
                    (doItem.text.localizedStandardContains(searchText) ||
                    (doItem.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    doItem.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Do> { doItem in
                    doItem.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Do> { doItem in
                doItem.text.localizedStandardContains(searchText) ||
                (doItem.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar with dos list
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("Search dos", text: $searchText)
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
                    if displayedDos.isEmpty && !isLoading {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "video.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                            }
                            VStack(spacing: 6) {
                                Text("No Screen Recordings")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Hold Shift + tap-tap your hotkey\nto record your screen with audio")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(2)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(displayedDos) { doItem in
                                    DoListItem(
                                        doItem: doItem,
                                        isSelected: selectedDo == doItem,
                                        isChecked: selectedDos.contains(doItem),
                                        onSelect: { selectedDo = doItem },
                                        onToggleCheck: { toggleSelection(doItem) }
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
                            .padding(.bottom, !selectedDos.isEmpty ? 50 : 0)
                        }
                    }

                    if !selectedDos.isEmpty {
                        selectionToolbar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: 320)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Center pane with do detail
            Group {
                if let doItem = selectedDo {
                    DoDetailView(doItem: doItem)
                        .id(doItem.id)
                } else {
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                                .frame(width: 120, height: 80)
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        VStack(spacing: 4) {
                            Text("Select a Recording")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Choose a screen recording from the list")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .alert("Delete Selected Dos?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedDos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete \(selectedDos.count) do\(selectedDos.count == 1 ? "" : "s")?")
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
        .onChange(of: latestDoIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .doCreated)) { _ in
            guard isViewCurrentlyVisible else { return }
            Task {
                await resetPagination()
                await loadInitialContent()
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { copySelectedDos() }) {
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

            Text("\(selectedDos.count) selected")
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
            displayedDos = items
            lastTimestamp = items.last?.timestamp
            hasMoreContent = items.count == pageSize
        } catch {
            print("Error loading dos: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newItems = try modelContext.fetch(cursorQueryDescriptor(after: lastTimestamp))
            displayedDos.append(contentsOf: newItems)
            self.lastTimestamp = newItems.last?.timestamp
            hasMoreContent = newItems.count == pageSize
        } catch {
            print("Error loading more dos: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedDos = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    private func performDeletion(for doItem: Do) {
        // Delete video file
        if let urlString = doItem.videoFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting video file: \(error.localizedDescription)")
            }
        }

        // Delete audio file
        if let urlString = doItem.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        if selectedDo == doItem {
            selectedDo = nil
        }

        selectedDos.remove(doItem)
        modelContext.delete(doItem)
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

    private func deleteSelectedDos() {
        for doItem in selectedDos {
            performDeletion(for: doItem)
        }
        selectedDos.removeAll()

        Task {
            await saveAndReload()
        }
    }

    private func toggleSelection(_ doItem: Do) {
        if selectedDos.contains(doItem) {
            selectedDos.remove(doItem)
        } else {
            selectedDos.insert(doItem)
        }
    }

    private func copySelectedDos() {
        let dosText = selectedDos
            .sorted { $0.timestamp > $1.timestamp }
            .map { $0.enhancedText ?? $0.text }
            .joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dosText, forType: .string)
    }
}
