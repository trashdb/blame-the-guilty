import AppKit

enum NotificationStyle {
    case punishment
    case info
}

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

private func playInfoSound() {
    if let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Ping.aiff", byReference: false) {
        sound.volume = 0.3
        sound.play()
    }
}

func showNotification(title: String, body: String, subtitle: String? = nil, actionURL: URL? = nil, style: NotificationStyle = .punishment) {
    if style == .punishment {
        playPunishmentSound()
    } else {
        playInfoSound()
    }
    NotificationBanner.shared.show(title: title, body: body, subtitle: subtitle, actionURL: actionURL, style: style)
}
