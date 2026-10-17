import SwiftUI
import AppKit

/// Local builds have a new signing identity, so existing TCC grants may need renewal.
struct CapturePermissionView: View {
    @State private var screenAllowed = scPerm
    @State private var accessibilityAllowed = axPerm

    var body: some View {
        Group {
            if screenAllowed && accessibilityAllowed {
                ContentView()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                    Text("Allow Topit to Capture Windows")
                        .font(.title2.bold())
                    Text("Screen Recording captures the selected window. Accessibility lets you select and focus windows. A locally rebuilt app may need these permissions again.")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: screenAllowed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(screenAllowed ? .green : .secondary)
                        Button("Open Screen Recording Settings") {
                            openPrivacy("Privacy_ScreenCapture")
                        }
                    }
                    HStack {
                        Image(systemName: accessibilityAllowed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(accessibilityAllowed ? .green : .secondary)
                        Button("Open Accessibility Settings") {
                            openPrivacy("Privacy_Accessibility")
                        }
                    }
                    Button("Recheck Permissions", action: refresh)
                    Text("After granting permissions, quit and reopen Topit if capture is still unavailable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(width: 480)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        screenAllowed = CGPreflightScreenCaptureAccess()
        accessibilityAllowed = AXIsProcessTrusted()
        scPerm = screenAllowed
        axPerm = accessibilityAllowed
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
