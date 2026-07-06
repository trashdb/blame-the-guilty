import AppKit

func setupNotifications() {}

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

func showNotification(title: String, body: String, subtitle: String? = nil, actionURL: URL? = nil) {
    playPunishmentSound()
    NotificationBanner.shared.show(title: title, body: body, subtitle: subtitle, actionURL: actionURL)
}
