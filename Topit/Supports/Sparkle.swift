import SwiftUI

// Official releases would overwrite the region feature. This local build has no updater.
private let localUpdateMessage = "This local build includes region pinning. Official updates would replace this feature; automatic updates are disabled."

func showLocalUpdateNotice() {
    createAlert(title: "Topit", message: localUpdateMessage, button1: "OK").runModal()
}

struct CheckForUpdatesView: View {
    var body: some View {
        Button("Check for Updates…", action: showLocalUpdateNotice)
    }
}

struct UpdaterSettingsView: View {
    var body: some View {
        Text(localUpdateMessage.local)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
