import AppKit

// MARK: - Setup (kept for compatibility, no-op now)
func setupNotifications() {}

// MARK: - Sound

private func playPunishmentSound() {
    let paths = [
        "/System/Library/Sounds/Glass.aiff",
        "/System/Library/Sounds/Ping.aiff",
        "/System/Library/Sounds/Basso.aiff"
    ]
    for path in paths {
        if let sound = NSSound(contentsOfFile: path, byReference: false) {
            sound.volume = 1.0
            sound.play()
            break
        }
    }
}

// MARK: - Show notification

/// Shows a custom floating banner in the top-right corner (like system notifications).
/// Uses NSPanel — no bundle/signing requirements, click opens the workflow URL directly.
func showNotification(title: String, body: String, subtitle: String? = nil, actionURL: URL? = nil) {
    playPunishmentSound()
    NotificationBanner.shared.show(title: title, body: body, subtitle: subtitle, actionURL: actionURL)
}
