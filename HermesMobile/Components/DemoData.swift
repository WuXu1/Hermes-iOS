import Foundation

nonisolated enum DemoData {

    // MARK: - Chat

    static let sampleConversation: Conversation = {
        let cal = Calendar.current
        let now = Date.now
        return Conversation(
            title: "Hermes Agent",
            messages: [
                Message(
                    sender: .hermes,
                    content: "Good morning! I've been reviewing your schedule for today. You have a team standup at 10 AM and a design review at 2 PM. Would you like me to prepare any talking points?",
                    timestamp: cal.date(byAdding: .hour, value: -3, to: now) ?? now,
                    status: .delivered
                ),
                Message(
                    sender: .user,
                    content: "Yes please, especially for the design review. Can you pull together the latest mockups and any feedback from last week?",
                    timestamp: cal.date(byAdding: .hour, value: -3, to: now)?.addingTimeInterval(120) ?? now,
                    status: .delivered
                ),
                Message(
                    sender: .hermes,
                    content: "Done. I've compiled the latest Figma exports and summarized the three key feedback themes from last week's session: navigation clarity, color contrast accessibility, and onboarding flow length. I've also flagged two open questions from Elena's comments. Want me to create a brief deck?",
                    timestamp: cal.date(byAdding: .hour, value: -2, to: now) ?? now,
                    status: .delivered
                ),
                Message(
                    sender: .user,
                    content: "That would be great. Keep it to 5 slides max.",
                    timestamp: cal.date(byAdding: .hour, value: -2, to: now)?.addingTimeInterval(60) ?? now,
                    status: .delivered
                ),
                Message(
                    sender: .hermes,
                    content: "I'll have that ready within the hour. Also, I noticed your grocery delivery is scheduled for 4 PM today. Should I keep that or reschedule given the design review might run long?",
                    timestamp: cal.date(byAdding: .hour, value: -1, to: now) ?? now,
                    status: .delivered
                ),
                Message(
                    sender: .user,
                    content: "Good catch. Push it to 6 PM if possible.",
                    timestamp: cal.date(byAdding: .minute, value: -45, to: now) ?? now,
                    status: .delivered
                ),
                Message(
                    sender: .hermes,
                    content: "Rescheduled to 6 PM. Your delivery window is now 6:00-6:30 PM. I'll send you a reminder at 5:45. Is there anything else you'd like me to handle before the standup?",
                    timestamp: cal.date(byAdding: .minute, value: -30, to: now) ?? now,
                    status: .delivered
                ),
            ],
            lastActivity: cal.date(byAdding: .minute, value: -30, to: now) ?? now
        )
    }()

    // MARK: - Permissions

    static let sampleCapabilities: [DeviceCapability] = [
        DeviceCapability(
            permissionType: .location,
            status: .authorizedWhenInUse,
            statusDetail: "While Using • Full Accuracy"
        ),
        DeviceCapability(permissionType: .health, status: .notDetermined),
        DeviceCapability(permissionType: .notifications, status: .authorized),
        DeviceCapability(permissionType: .camera, status: .notDetermined),
        DeviceCapability(permissionType: .photos, status: .denied),
    ]

    // MARK: - Settings

    static let sampleUserSettings = UserSettings(
        userName: "Alex",
        avatarInitials: "A",
        notificationsEnabled: true,
        hapticFeedbackEnabled: true,
        environment: AppEnvironmentPolicy.currentBuild.defaultEnvironment,
        autoConnectOnLaunch: true
    )
}
