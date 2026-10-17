//
//  SettingsView.swift
//  Topit
//
//  Created by apple on 2024/11/19.
//

import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    private enum Section: String, CaseIterable {
        case general = "General", windows = "Windows", hotkeys = "Hotkey", filter = "App Filter"
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .windows: return "macwindow"
            case .hotkeys: return "keyboard"
            case .filter: return "line.3.horizontal.decrease.circle"
            }
        }
    }
    @State private var selected: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Section.allCases, id: \.self) { section in
                    Button {
                        selected = section
                    } label: {
                        Label(LocalizedStringKey(section.rawValue), systemImage: section.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(selected == section ? Color.accentColor.opacity(0.18) : .clear)
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 164)
            Divider()
            ScrollView {
                Group {
                    switch selected {
                    case .general: GeneralView()
                    case .windows: WindowView()
                    case .hotkeys: HotkeyView()
                    case .filter: FilterView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}

struct GeneralView: View {
    @AppStorage("showOnDock") private var showOnDock: Bool = true
    @AppStorage("showMenubar") private var showMenubar: Bool = true
    
    @State private var launchAtLogin: Bool = {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }()
    
    var body: some View {
        SForm {
            SGroupBox(label: "General") {
                if #available(macOS 13, *) {
                    SToggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            }catch{
                                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                            }
                        }
                    SDivider()
                }
                SToggle("Show Topit on Dock", isOn: $showOnDock)
                SDivider()
                SToggle("Show Topit on Menu Bar", isOn: $showMenubar)
            }
            SGroupBox(label: "Update") {
                UpdaterSettingsView()
            }
            VStack(spacing: 8) {
                CheckForUpdatesView()
                if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Topit v\(appVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: showMenubar) { newValue in statusBarItem.isVisible = newValue }
        .onChange(of: showOnDock) { newValue in
            if !newValue {
                NSApp.setActivationPolicy(.accessory)
                closeMainWindow()
            } else { NSApp.setActivationPolicy(.regular) }
        }
    }
}

struct WindowView: View {
    @AppStorage("showCloseButton") private var showCloseButton: Bool = true
    @AppStorage("showUnpinButton") private var showUnpinButton: Bool = true
    @AppStorage("showPauseButton") private var showPauseButton: Bool = true
    @AppStorage("buttonPosition") private var buttonPosition: Int = 0
    @AppStorage("mouseOverAction") private var mouseOverAction: Bool = true
    @AppStorage("keepFocus") private var keepFocus: Bool = false
    @AppStorage("autoAvoid") private var autoAvoid: Bool = true
    @AppStorage("showBorder") private var showBorder: Bool = false
    @AppStorage("maxFps") private var maxFps: Int = 65535
    
    var body: some View {
        SForm(spacing: 10) {
            SGroupBox(label: "Windows") {
                SPicker("Activate Pinned Window on", selection: $mouseOverAction,
                        tips: "When you select \"Left Click\" as the way to activate a window, you need to activate the window before moving it.") {
                    Text("Cursor Hover").tag(true)
                    Text(keepFocus ? "Double Click" : "Left Click").tag(false)
                }
                if !mouseOverAction {
                    SDivider()
                    SToggle("Prevent Focus Switching", isOn: $keepFocus,
                            tips: "Prevent keyboard input from being interrupted when the mouse passes over a pinned window.\nPlease note: You will need to double-click to activate pinned window after enabling this!")
                }
                SDivider()
                SPicker("Control Button Position", selection: $buttonPosition) {
                    Text("Top Leading").tag(0)
                    Text("Top Trailing").tag(2)
                    Text("Bottom Leading").tag(1)
                    Text("Bottom Trailing").tag(3)
                }
                SDivider()
                SPicker("Maximum Refresh Rate", selection: $maxFps) {
                    Text("30 Hz").tag(30)
                    Text("60 Hz").tag(60)
                    Text("120 Hz").tag(120)
                    Text("No Limit").tag(65535)
                }
            }
            SGroupBox {
                if #available (macOS 13, *) {
                    SToggle("Ducking Between Pinned Windows", isOn: $autoAvoid,
                            tips: "By enabling this, Topit will hide other pinned windows that overlap with the currently active window.")
                    SDivider()
                    SToggle("Add Border for Translucent Window", isOn: $showBorder)
                } else {
                    SToggle("Show Close Button", isOn: $showCloseButton)
                    SDivider()
                    SToggle("Show Unpin Button", isOn: $showUnpinButton)
                }
            }
        }
    }
}

struct HotkeyView: View {
    var body: some View {
        SForm(spacing: 10) {
            SGroupBox(label: "Hotkey") {
                SItem(label: "Select a Region to Pin") { KeyboardShortcuts.Recorder("", name: .selectRegion) }
                SDivider()
                SItem(label: "Select a Window to Pin") { KeyboardShortcuts.Recorder("", name: .selectWindow) }
                SDivider()
                SItem(label: "Open Window Selector"){ KeyboardShortcuts.Recorder("", name: .openMainPanel) }
            }
            SGroupBox {
                SItem(label: "Pin / Unpin Under-Mouse Window") { KeyboardShortcuts.Recorder("", name: .pinUnpin) }
                SDivider()
                SItem(label: "Pin / Unpin Frontmost Window") { KeyboardShortcuts.Recorder("", name: .pinUnpinTopmost) }
                SDivider()
                SItem(label: "Unpin All Pinned Windows"){ KeyboardShortcuts.Recorder("", name: .unpinAll) }
            }
        }
    }
}

struct FilterView: View {
    @AppStorage("noTitle") var noTitle = true
    
    var body: some View {
        SForm(spacing: 10, noSpacer: true) {
            SGroupBox(label: "App Filter") {
                SToggle("Show Windows with No Title", isOn: $noTitle)
            }
            SGroupBox {
                BundleSelector()
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let selectRegion = Self("selectRegion", default: .init(.t, modifiers: [.command, .shift]))
    static let selectWindow = Self("selectWindow")
    static let openMainPanel = Self("openMainPanel")
    static let pinUnpin = Self("pinUnpin")
    static let pinUnpinTopmost = Self("pinTopmost")
    static let unpinAll = Self("unpinAll")
}
