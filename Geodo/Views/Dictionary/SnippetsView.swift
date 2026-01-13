import SwiftUI
import SwiftData

/// View for managing voice snippets (voice shortcuts)
/// Inspired by Wispr Flow's snippets feature
struct SnippetsView: View {
    @Query private var snippets: [Snippet]
    @Environment(\.modelContext) private var modelContext
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var triggerText = ""
    @State private var expansionText = ""
    @State private var editingSnippet: Snippet? = nil
    @State private var showInfoPopover = false

    private var sortedSnippets: [Snippet] {
        snippets.sorted { $0.usageCount > $1.usageCount }
    }

    private var shouldShowAddButton: Bool {
        !triggerText.isEmpty || !expansionText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                Label {
                    Text("Create voice shortcuts that expand trigger phrases into full text")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Button(action: { showInfoPopover.toggle() }) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfoPopover) {
                        SnippetsInfoPopover()
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Trigger phrase (e.g., \"my email\")", text: $triggerText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                    .frame(width: 10)

                TextField("Expansion text", text: $expansionText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addSnippet() }

                if shouldShowAddButton {
                    Button(action: addSnippet) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(triggerText.isEmpty || expansionText.isEmpty)
                    .help("Add snippet")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            if !snippets.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Trigger")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                            .frame(width: 10)

                        Text("Expansion")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Uses")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedSnippets) { snippet in
                                SnippetRow(
                                    snippet: snippet,
                                    onDelete: { removeSnippet(snippet) },
                                    onEdit: { editingSnippet = snippet },
                                    onToggle: { toggleSnippet(snippet) }
                                )

                                if snippet.id != sortedSnippets.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .sheet(item: $editingSnippet) { snippet in
            EditSnippetSheet(snippet: snippet, modelContext: modelContext)
        }
        .alert("Snippet", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func addSnippet() {
        let trigger = triggerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let expansion = expansionText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trigger.isEmpty && !expansion.isEmpty else { return }

        // Check for duplicate triggers
        if SnippetService.shared.triggerExists(trigger, in: modelContext) {
            alertMessage = "A snippet with trigger '\(trigger)' already exists"
            showAlert = true
            return
        }

        let newSnippet = Snippet(trigger: trigger, expansion: expansion)
        modelContext.insert(newSnippet)

        do {
            try modelContext.save()
            triggerText = ""
            expansionText = ""
        } catch {
            modelContext.delete(newSnippet)
            alertMessage = "Failed to add snippet: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func removeSnippet(_ snippet: Snippet) {
        modelContext.delete(snippet)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            alertMessage = "Failed to remove snippet: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func toggleSnippet(_ snippet: Snippet) {
        snippet.isEnabled.toggle()
        try? modelContext.save()
    }
}

struct SnippetsInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How Voice Snippets Work")
                .font(.headline)

            Text("When you speak a trigger phrase during recording, it gets automatically replaced with your expansion text.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Examples")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                SnippetExampleRow(trigger: "my email", expansion: "john@example.com")
                SnippetExampleRow(trigger: "my address", expansion: "123 Main St, City, ST 12345")
                SnippetExampleRow(trigger: "meeting link", expansion: "https://zoom.us/j/123456789")
                SnippetExampleRow(trigger: "sign off", expansion: "Best regards,\nJohn Smith")
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct SnippetExampleRow: View {
    let trigger: String
    let expansion: String

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Say:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\"\(trigger)\"")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Expands to:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(expansion)
                    .font(.callout)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(.textBackgroundColor))
        .cornerRadius(6)
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onToggle: () -> Void
    @State private var isEditHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { snippet.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Text(snippet.trigger)
                .font(.system(size: 13))
                .foregroundColor(snippet.isEnabled ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            Text(snippet.expansion)
                .font(.system(size: 13))
                .foregroundColor(snippet.isEnabled ? .primary : .secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(snippet.usageCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(isEditHovered ? .accentColor : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("Edit snippet")
                .onHover { hover in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditHovered = hover
                    }
                }

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isDeleteHovered ? .red : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("Remove snippet")
                .onHover { hover in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDeleteHovered = hover
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .opacity(snippet.isEnabled ? 1 : 0.6)
    }
}

struct EditSnippetSheet: View {
    let snippet: Snippet
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    @State private var trigger: String
    @State private var expansion: String
    @State private var showAlert = false
    @State private var alertMessage = ""

    init(snippet: Snippet, modelContext: ModelContext) {
        self.snippet = snippet
        self.modelContext = modelContext
        _trigger = State(initialValue: snippet.trigger)
        _expansion = State(initialValue: snippet.expansion)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Snippet")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trigger phrase")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("Trigger", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Expansion text")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextEditor(text: $expansion)
                        .font(.body)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.isEmpty || expansion.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func saveChanges() {
        let newTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let newExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !newTrigger.isEmpty && !newExpansion.isEmpty else { return }

        // Check for duplicate trigger (excluding current snippet)
        if SnippetService.shared.triggerExists(newTrigger, in: modelContext, excluding: snippet.id) {
            alertMessage = "A snippet with trigger '\(newTrigger)' already exists"
            showAlert = true
            return
        }

        snippet.trigger = newTrigger
        snippet.expansion = newExpansion

        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertMessage = "Failed to save changes: \(error.localizedDescription)"
            showAlert = true
        }
    }
}
