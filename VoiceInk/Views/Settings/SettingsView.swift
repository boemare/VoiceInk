import SwiftUI
import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 1.0
    @State private var showResetOnboardingAlert = false
    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    @State private var isCustomCancelEnabled = false
    @State private var expandedSections: Set<ExpandableSection> = []

    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PermissionsSettingsSection(hotkeyManager: hotkeyManager)

                AudioInputSettingsSection()

                SettingsSection(
                    icon: "command.circle",
                    title: "VoiceInk Shortcuts",
                    subtitle: "Choose how you want to trigger VoiceInk"
                ) {
                    VStack(alignment: .leading, spacing: 18) {
                        hotkeyView(
                            title: "Hotkey 1",
                            binding: $hotkeyManager.selectedHotkey1,
                            shortcutName: .toggleMiniRecorder
                        )

                        if hotkeyManager.selectedHotkey2 != .none {
                            Divider()
                            hotkeyView(
                                title: "Hotkey 2",
                                binding: $hotkeyManager.selectedHotkey2,
                                shortcutName: .toggleMiniRecorder2,
                                isRemovable: true,
                                onRemove: {
                                    withAnimation { hotkeyManager.selectedHotkey2 = .none }
                                }
                            )
                        }

                        if hotkeyManager.selectedHotkey1 != .none && hotkeyManager.selectedHotkey2 == .none {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation { hotkeyManager.selectedHotkey2 = .rightOption }
                                }) {
                                    Label("Add another hotkey", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }

                        Text("Quick tap to start hands-free recording (tap again to stop). Press and hold for push-to-talk (release to stop recording).")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsSection(
                    icon: "keyboard.badge.ellipsis",
                    title: "Other App Shortcuts",
                    subtitle: "Additional shortcuts for VoiceInk"
                ) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Paste Last Transcript (Original)
                        HStack(spacing: 12) {
                            Text("Paste Last Transcript(Original)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            KeyboardShortcuts.Recorder(for: .pasteLastTranscription)
                                .controlSize(.small)
                            
                            InfoTip(
                                title: "Paste Last Transcript(Original)",
                                message: "Shortcut for pasting the most recent transcription."
                            )
                            
                            Spacer()
                        }

                        // Paste Last Transcript (Enhanced)
                        HStack(spacing: 12) {
                            Text("Paste Last Transcript(Enhanced)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            KeyboardShortcuts.Recorder(for: .pasteLastEnhancement)
                                .controlSize(.small)
                            
                            InfoTip(
                                title: "Paste Last Transcript(Enhanced)",
                                message: "Pastes the enhanced transcript if available, otherwise falls back to the original."
                            )
                            
                            Spacer()
                        }

                        

                        // Retry Last Transcription
                        HStack(spacing: 12) {
                            Text("Retry Last Transcription")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)

                            KeyboardShortcuts.Recorder(for: .retryLastTranscription)
                                .controlSize(.small)

                            InfoTip(
                                title: "Retry Last Transcription",
                                message: "Re-transcribe the last recorded audio using the current model and copy the result."
                            )

                            Spacer()
                        }

                        Divider()



                        ExpandableToggleSection(
                            section: .customCancel,
                            title: "Custom Cancel Shortcut",
                            helpText: "Shortcut for cancelling the current recording session. Default: double-tap Escape.",
                            isEnabled: $isCustomCancelEnabled,
                            expandedSections: $expandedSections
                        ) {
                            HStack(spacing: 12) {
                                Text("Cancel Shortcut")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                KeyboardShortcuts.Recorder(for: .cancelRecorder)
                                    .controlSize(.small)

                                Spacer()
                            }
                        }
                        .onChange(of: isCustomCancelEnabled) { _, newValue in
                            if !newValue {
                                KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder)
                            }
                        }

                        Divider()

                        ExpandableToggleSection(
                            section: .middleClick,
                            title: "Enable Middle-Click Toggle",
                            helpText: "Use middle mouse button to toggle VoiceInk recording.",
                            isEnabled: $hotkeyManager.isMiddleClickToggleEnabled,
                            expandedSections: $expandedSections
                        ) {
                            HStack(spacing: 8) {
                                Text("Activation Delay")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                TextField("", value: $hotkeyManager.middleClickActivationDelay, formatter: {
                                    let formatter = NumberFormatter()
                                    formatter.numberStyle = .none
                                    formatter.minimum = 0
                                    return formatter
                                }())
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(5)
                                .frame(width: 70)

                                Text("ms")
                                    .foregroundColor(.secondary)

                                Spacer()
                            }
                        }
                    }
                }

                SettingsSection(
                    icon: "speaker.wave.2.bubble.left.fill",
                    title: "Recording Feedback",
                    subtitle: "Customize app & system feedback"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ExpandableToggleSection(
                            section: .soundFeedback,
                            title: "Sound feedback",
                            helpText: "Play sounds when recording starts and stops",
                            isEnabled: $soundManager.isEnabled,
                            expandedSections: $expandedSections
                        ) {
                            CustomSoundSettingsView()
                        }

                        Divider()

                        ExpandableToggleSection(
                            section: .systemMute,
                            title: "Mute system audio during recording",
                            helpText: "Automatically mute system audio when recording starts and restore when recording stops",
                            isEnabled: $mediaController.isSystemMuteEnabled,
                            expandedSections: $expandedSections
                        ) {
                            HStack(spacing: 8) {
                                Text("Resume Delay")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                Picker("", selection: $mediaController.audioResumptionDelay) {
                                    Text("0s").tag(0.0)
                                    Text("1s").tag(1.0)
                                    Text("2s").tag(2.0)
                                    Text("3s").tag(3.0)
                                    Text("4s").tag(4.0)
                                    Text("5s").tag(5.0)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)

                                InfoTip(
                                    title: "Audio Resume Delay",
                                    message: "Delay before unmuting system audio after recording stops. Useful for Bluetooth headphones that need time to switch from microphone mode back to high-quality audio mode. Recommended: 2s for AirPods/Bluetooth headphones, 0s for wired headphones."
                                )

                                Spacer()
                            }
                        }

                        Divider()

                        ExpandableToggleSection(
                            section: .clipboardRestore,
                            title: "Restore clipboard after paste",
                            helpText: "When enabled, VoiceInk will restore your original clipboard content after pasting the transcription.",
                            isEnabled: $restoreClipboardAfterPaste,
                            expandedSections: $expandedSections
                        ) {
                            HStack(spacing: 8) {
                                Text("Restore Delay")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                Picker("", selection: $clipboardRestoreDelay) {
                                    Text("1s").tag(1.0)
                                    Text("2s").tag(2.0)
                                    Text("3s").tag(3.0)
                                    Text("4s").tag(4.0)
                                    Text("5s").tag(5.0)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)

                                Spacer()
                            }
                        }

                    }
                }

                PowerModeSettingsSection()

                ExperimentalFeaturesSection()

                SettingsSection(
                    icon: "rectangle.on.rectangle",
                    title: "Recorder Style",
                    subtitle: "Choose your preferred recorder interface"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select how you want the recorder to appear on your screen.")
                            .settingsDescription()
                        
                        Picker("Recorder Style", selection: $whisperState.recorderType) {
                            Text("Notch Recorder").tag("notch")
                            Text("Mini Recorder").tag("mini")
                        }
                        .pickerStyle(.radioGroup)
                        .padding(.vertical, 4)
                    }
                }

                SettingsSection(
                    icon: "doc.on.clipboard",
                    title: "Paste Method",
                    subtitle: "Choose how text is pasted"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select the method used to paste text. Use AppleScript if you have a non-standard keyboard layout.")
                            .settingsDescription()

                        Toggle("Use AppleScript Paste Method", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "UseAppleScriptPaste") },
                            set: { UserDefaults.standard.set($0, forKey: "UseAppleScriptPaste") }
                        ))
                        .toggleStyle(.switch)
                    }
                }

                SettingsSection(
                    icon: "gear",
                    title: "General",
                    subtitle: "Appearance, startup, and updates"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Hide Dock Icon (Menu Bar Only)", isOn: $menuBarManager.isMenuBarOnly)
                            .toggleStyle(.switch)
                        
                        LaunchAtLogin.Toggle()
                            .toggleStyle(.switch)

                        Toggle("Enable automatic update checks", isOn: $autoUpdateCheck)
                            .toggleStyle(.switch)
                            .onChange(of: autoUpdateCheck) { _, newValue in
                                updaterViewModel.toggleAutoUpdates(newValue)
                            }
                        
                        Toggle("Show app announcements", isOn: $enableAnnouncements)
                            .toggleStyle(.switch)
                            .onChange(of: enableAnnouncements) { _, newValue in
                                if newValue {
                                    AnnouncementsService.shared.start()
                                } else {
                                    AnnouncementsService.shared.stop()
                                }
                            }
                        
                        Button("Check for Updates Now") {
                            updaterViewModel.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!updaterViewModel.canCheckForUpdates)
                        
                        Divider()

                        Button("Reset Onboarding") {
                            showResetOnboardingAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                SettingsSection(
                    icon: "lock.shield",
                    title: "Data & Privacy",
                    subtitle: "Control transcript history and storage"
                ) {
                    AudioCleanupSettingsView()
                }
                
                SettingsSection(
                    icon: "arrow.up.arrow.down.circle",
                    title: "Data Management",
                    subtitle: "Import or export your settings"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export your custom prompts, power modes, word replacements, keyboard shortcuts, and app preferences to a backup file. API keys are not included in the export.")
                            .settingsDescription()

                        HStack(spacing: 12) {
                            Button {
                                ImportExportService.shared.importSettings(
                                    enhancementService: enhancementService, 
                                    whisperPrompt: whisperState.whisperPrompt, 
                                    hotkeyManager: hotkeyManager, 
                                    menuBarManager: menuBarManager, 
                                    mediaController: MediaController.shared, 
                                    playbackController: PlaybackController.shared,
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Import Settings...", systemImage: "arrow.down.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)

                            Button {
                                ImportExportService.shared.exportSettings(
                                    enhancementService: enhancementService,
                                    whisperPrompt: whisperState.whisperPrompt,
                                    hotkeyManager: hotkeyManager,
                                    menuBarManager: menuBarManager,
                                    mediaController: MediaController.shared,
                                    playbackController: PlaybackController.shared,
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Export Settings...", systemImage: "arrow.up.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                        }
                    }
                }

                SettingsSection(
                    icon: "ant.circle",
                    title: "Diagnostics",
                    subtitle: "Export logs for troubleshooting"
                ) {
                    DiagnosticsSettingsView()
                }

                // Additional Settings Navigation
                SettingsSection(
                    icon: "ellipsis.circle",
                    title: "More Settings",
                    subtitle: "Additional configuration options"
                ) {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(
                            icon: "brain.head.profile",
                            title: "AI Models",
                            subtitle: "Manage transcription models"
                        ) {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "AI Models"]
                            )
                        }

                        Divider().padding(.vertical, 8)

                        SettingsNavigationRow(
                            icon: "wand.and.stars",
                            title: "Enhancement",
                            subtitle: "AI enhancement settings"
                        ) {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Enhancement"]
                            )
                        }

                        Divider().padding(.vertical, 8)

                        SettingsNavigationRow(
                            icon: "character.book.closed.fill",
                            title: "Dictionary",
                            subtitle: "Word replacements and vocabulary"
                        ) {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Dictionary"]
                            )
                        }

                        Divider().padding(.vertical, 8)

                        SettingsNavigationRow(
                            icon: "waveform.circle.fill",
                            title: "Transcribe Audio",
                            subtitle: "Transcribe audio files"
                        ) {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Transcribe Audio"]
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            isCustomCancelEnabled = KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil
        }
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                // Defer state change to avoid layout issues while alert dismisses
                DispatchQueue.main.async {
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text("Are you sure you want to reset the onboarding? You'll see the introduction screens again the next time you launch the app.")
        }
    }
    
    @ViewBuilder
    private func hotkeyView(
        title: String,
        binding: Binding<HotkeyManager.HotkeyOption>,
        shortcutName: KeyboardShortcuts.Name,
        isRemovable: Bool = false,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Menu {
                ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { option in
                    Button(action: {
                        binding.wrappedValue = option
                    }) {
                        HStack {
                            Text(option.displayName)
                            if binding.wrappedValue == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(binding.wrappedValue.displayName)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            
            if binding.wrappedValue == .custom {
                KeyboardShortcuts.Recorder(for: shortcutName)
                    .controlSize(.small)
            }
            
            Spacer()
            
            if isRemovable {
                Button(action: {
                    onRemove?()
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let content: Content
    var showWarning: Bool = false
    
    init(icon: String, title: String, subtitle: String, showWarning: Bool = false, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showWarning = showWarning
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(showWarning ? .red : .accentColor)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(showWarning ? .red : .secondary)
                }
                
                if showWarning {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .help("Permission required for VoiceInk to function properly")
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: showWarning, useAccentGradientWhenSelected: true))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(showWarning ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

// Add this extension for consistent description text styling
extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PermissionsSettingsSection: View {
    @ObservedObject var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager()

    private var allPermissionsGranted: Bool {
        hotkeyManager.selectedHotkey1 != .none &&
        permissionManager.audioPermissionStatus == .authorized &&
        permissionManager.isAccessibilityEnabled &&
        permissionManager.isScreenRecordingEnabled
    }

    var body: some View {
        SettingsSection(
            icon: "shield.lefthalf.filled",
            title: "Permissions",
            subtitle: "Required permissions for VoiceInk to function",
            showWarning: !allPermissionsGranted
        ) {
            VStack(spacing: 12) {
                PermissionRow(
                    icon: "keyboard",
                    title: "Keyboard Shortcut",
                    isGranted: hotkeyManager.selectedHotkey1 != .none,
                    action: {
                        // Already in settings, just scroll to shortcuts section
                    },
                    checkPermission: { permissionManager.checkKeyboardShortcut() }
                )

                Divider()

                PermissionRow(
                    icon: "mic",
                    title: "Microphone Access",
                    isGranted: permissionManager.audioPermissionStatus == .authorized,
                    action: {
                        if permissionManager.audioPermissionStatus == .notDetermined {
                            permissionManager.requestAudioPermission()
                        } else {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    },
                    checkPermission: { permissionManager.checkAudioPermissionStatus() }
                )

                Divider()

                PermissionRow(
                    icon: "hand.raised",
                    title: "Accessibility Access",
                    isGranted: permissionManager.isAccessibilityEnabled,
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    checkPermission: { permissionManager.checkAccessibilityPermissions() }
                )

                Divider()

                PermissionRow(
                    icon: "rectangle.on.rectangle",
                    title: "Screen Recording",
                    isGranted: permissionManager.isScreenRecordingEnabled,
                    action: {
                        permissionManager.requestScreenRecordingPermission()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    checkPermission: { permissionManager.checkScreenRecordingPermission() }
                )
            }
        }
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let isGranted: Bool
    let action: () -> Void
    let checkPermission: () -> Void
    @State private var isRefreshing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "\(icon).fill" : icon)
                .font(.system(size: 16))
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isRefreshing = true
                }
                checkPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isRefreshing = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
            }
            .buttonStyle(.plain)

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct AudioInputSettingsSection: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared

    var body: some View {
        SettingsSection(
            icon: "mic.fill",
            title: "Audio Input",
            subtitle: "Configure your microphone preferences"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Input Mode Picker
                HStack {
                    Text("Input Mode")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Picker("", selection: Binding(
                        get: { audioDeviceManager.inputMode },
                        set: { audioDeviceManager.selectInputMode($0) }
                    )) {
                        ForEach(AudioInputMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                Divider()

                // Current Device Display
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Device")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(currentDeviceName)
                            .font(.system(size: 13, weight: .medium))
                    }

                    Spacer()

                    Button(action: { audioDeviceManager.loadAvailableDevices() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                // Device selection for custom mode
                if audioDeviceManager.inputMode == .custom {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Device")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                            AudioDeviceRow(
                                name: device.name,
                                isSelected: audioDeviceManager.selectedDeviceID == device.id,
                                isActive: audioDeviceManager.getCurrentDevice() == device.id
                            ) {
                                audioDeviceManager.selectDevice(id: device.id)
                            }
                        }
                    }
                }

                // Prioritized devices hint
                if audioDeviceManager.inputMode == .prioritized {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Priority Order")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        if audioDeviceManager.prioritizedDevices.isEmpty {
                            Text("No prioritized devices set")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(audioDeviceManager.prioritizedDevices.sorted(by: { $0.priority < $1.priority })) { device in
                                HStack(spacing: 8) {
                                    Text("\(device.priority + 1).")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    Text(device.name)
                                        .font(.system(size: 13))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var currentDeviceName: String {
        let deviceId = audioDeviceManager.getCurrentDevice()
        if let device = audioDeviceManager.availableDevices.first(where: { $0.id == deviceId }) {
            return device.name
        }
        return audioDeviceManager.getSystemDefaultDeviceName() ?? "No device"
    }
}

struct AudioDeviceRow: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .blue : .secondary)

                Text(name)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
