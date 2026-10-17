import Foundation

@main
struct ShortcutPreferencesTests {
    static func main() throws {
        let suite = "Topit.Tests.ShortcutPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let desired = "{\"carbonModifiers\":768,\"carbonKeyCode\":17}"
        let previousRegion = "{\"carbonModifiers\":6656,\"carbonKeyCode\":35}"
        defaults.set(desired, forKey: "KeyboardShortcuts_pinUnpin")
        defaults.set(previousRegion, forKey: "KeyboardShortcuts_selectRegion")
        defaults.set("{\"carbonModifiers\":256,\"carbonKeyCode\":3}", forKey: "KeyboardShortcuts_openMainPanel")
        ShortcutPreferences.migrateRegionShortcut(in: defaults)
        let raw = defaults.string(forKey: "KeyboardShortcuts_selectRegion")!.data(using: .utf8)!
        let binding = try JSONSerialization.jsonObject(with: raw) as! [String: Int]
        check(binding["carbonKeyCode"] == 17, "T targets region capture")
        check(binding["carbonModifiers"] == 768, "Command and Shift only")
        check(defaults.object(forKey: "KeyboardShortcuts_pinUnpin") as? Bool == false,
              "whole-window command cannot consume Command-Shift-T")
        check(defaults.string(forKey: "KeyboardShortcuts_openMainPanel") != nil, "unrelated custom shortcut preserved")
        check(defaults.bool(forKey: ShortcutPreferences.migrationKey), "migration recorded")
        defaults.set(previousRegion, forKey: "KeyboardShortcuts_selectRegion")
        ShortcutPreferences.migrateRegionShortcut(in: defaults)
        check(defaults.string(forKey: "KeyboardShortcuts_selectRegion") == previousRegion,
              "later user customization is not overwritten on every launch")
        print("Passed \(checks) shortcut migration checks")
    }
}
