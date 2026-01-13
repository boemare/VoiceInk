import Foundation
import AppKit
import os

/// Detects if a meeting application is currently running or in the foreground
final class MeetingAppDetectionService {

    static let shared = MeetingAppDetectionService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingDetection")

    /// Known meeting application bundle identifiers and their display names
    private let meetingApps: [String: String] = [
        // Video conferencing
        "us.zoom.xos": "Zoom",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.microsoft.teams": "Teams",
        "com.microsoft.teams2": "Teams",
        "com.skype.skype": "Skype",
        "com.apple.FaceTime": "FaceTime",
        "com.discord.Discord": "Discord",
        "com.slack.Slack": "Slack",
        "com.amazon.Amazon-Chime": "Chime",
        "com.bluejeans.BlueJeans": "BlueJeans",
        "com.ringcentral.ringcentralclassic": "RingCentral",
        "com.ringcentral.glip": "RingCentral",
        "com.logmein.GoToMeeting": "GoToMeeting",
        "com.around.Electron": "Around",
        "tv.parsec.www": "Parsec",
        "com.loom.desktop": "Loom",
        "com.tuple.app": "Tuple",
        "com.pop.pop.app": "Pop",
        "com.teamviewer.TeamViewer": "TeamViewer",
        "com.brave.Browser": "Brave",  // For web-based meetings
    ]

    /// Browser apps that might be running web-based meetings (Google Meet, etc.)
    private let browserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",  // Arc
        "com.operasoftware.Opera",
    ]

    private init() {}

    /// Checks if any meeting app is currently running
    /// Returns the name of the first detected meeting app, or nil if none found
    func detectRunningMeetingApp() -> String? {
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            if let meetingName = meetingApps[bundleId] {
                logger.info("Detected meeting app: \(meetingName) (\(bundleId))")
                return meetingName
            }
        }

        return nil
    }

    /// Checks if the frontmost app is a meeting application
    /// Returns the name of the meeting app if detected, or nil
    func detectFrontmostMeetingApp() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            return nil
        }

        if let meetingName = meetingApps[bundleId] {
            logger.info("Frontmost app is meeting: \(meetingName)")
            return meetingName
        }

        // Check if it's a browser (could be running Google Meet, etc.)
        if browserBundleIds.contains(bundleId) {
            // We can't easily detect if a browser tab is running Meet
            // For now, we'll consider any browser as potentially a meeting
            // A more sophisticated approach would use accessibility APIs
            return nil
        }

        return nil
    }

    /// Checks if any meeting app is running and returns meeting info
    /// Prioritizes the frontmost app if it's a meeting app
    func detectMeetingContext() -> MeetingContext? {
        // First check frontmost app
        if let frontAppName = detectFrontmostMeetingApp() {
            return MeetingContext(
                isMeeting: true,
                sourceApp: frontAppName,
                isFrontmost: true
            )
        }

        // Then check any running meeting app
        if let runningAppName = detectRunningMeetingApp() {
            return MeetingContext(
                isMeeting: true,
                sourceApp: runningAppName,
                isFrontmost: false
            )
        }

        return nil
    }
}

/// Context information about a detected meeting
struct MeetingContext {
    let isMeeting: Bool
    let sourceApp: String
    let isFrontmost: Bool
}
