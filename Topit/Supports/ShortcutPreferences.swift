import Foundation
import Carbon.HIToolbox

/// Applied before KeyboardShortcuts registers handlers. Explicit one-time migration requested by the user.
enum ShortcutPreferences {
    private struct Binding: Codable, Equatable {
        let carbonModifiers: Int
        let carbonKeyCode: Int
    }
    static let migrationKey = "regionCommandShiftTShortcutMigrated"

    static func migrateRegionShortcut(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let target = Binding(carbonModifiers: Int(cmdKey | shiftKey), carbonKeyCode: Int(kVK_ANSI_T))
        // Prevent the old whole-window action from consuming the same chord.
        for name in ["pinUnpin", "pinTopmost", "selectWindow", "openMainPanel", "unpinAll"] {
            let key = "KeyboardShortcuts_" + name
            if let raw = defaults.string(forKey: key)?.data(using: .utf8),
               let binding = try? JSONDecoder().decode(Binding.self, from: raw), binding == target {
                defaults.set(false, forKey: key)
            }
        }
        if let encoded = try? JSONEncoder().encode(target), let value = String(data: encoded, encoding: .utf8) {
            defaults.set(value, forKey: "KeyboardShortcuts_selectRegion")
            defaults.set(true, forKey: migrationKey)
        }
    }
}
