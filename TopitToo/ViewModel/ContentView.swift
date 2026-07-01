//
//  ContentView.swift
//  TopitToo
//
//  Created by apple on 2024/11/17.
//

import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject var viewModel = WindowSelectorViewModel()
    @State private var selected = [SCWindow]()
    @State private var display: SCDisplay!
    @State private var selectedTab = 0
    @State private var sheeting: Bool = false
    @State private var overQuit: Bool = true
    @State private var panel: NSWindow?
    @AppStorage("noTitle") var noTitle = true
    
    var body: some View {
        VStack(spacing: 0) {
            if isMacOS12 || isMacOS13 {
                HStack {
                    Spacer()
                    HoverButton(action: {
                        openSettingPanel()
                    }, label: {
                        Image(systemName: "gear").font(.system(size: 14, weight: .medium))
                    }).help("Open Settings")
                    HoverButton(action: {
                        selected.removeAll()
                        viewModel.setupStreams(filter: !noTitle)
                    }, label: {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .medium))
                    }).help("Update Window List")
                    HoverButton(action: {
                        //panel?.close()
                        WindowHighlighter.shared.registerMouseMonitor()
                    }, label: {
                        Image("window.select")
                            .resizable().scaledToFit()
                            .frame(width: 20)
                    })
                    .help("Select Window Directly")
                    Button(action: {
                        if let window = selected.first, let panel = panel {
                            _ = SCManager.updateAvailableContentSync()
                            if SCManager.getWindows().contains(window) {
                                createNewWindow(display: display, window: window)
                                panel.close()
                            } else {
                                let alert = createAlert(level: .critical, title: "Error", message: "This window is not available!", button1: "OK")
                                alert.beginSheetModal(for: panel) { _ in
                                    selected.removeAll()
                                    viewModel.setupStreams(filter: !noTitle)
                                }
                            }
                        }
                    }, label: {
                        Text(" TopitToo! ")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(selected.isEmpty ? Color.secondary.opacity(0.5) : .blue)
                            .cornerRadius(5)
                    })
                    .buttonStyle(.plain)
                    .disabled(selected.isEmpty)
                    .padding(.leading, 2)
                }
            }
            TabView(selection: $selectedTab) {
                let allApps = viewModel.windowThumbnails.sorted(by: { $0.key.displayID < $1.key.displayID })
                ForEach(allApps, id: \.key) { element in
                    let (screen, thumbnails) = element
                    let index = allApps.firstIndex(where: { $0.key == screen }) ?? 0
                    ScrollView(showsIndicators:false) {
                        VStack(spacing: 10) {
                            ForEach(0..<thumbnails.count/4 + 1, id: \.self) { rowIndex in
                                HStack(spacing: 16) {
                                    ForEach(0..<4, id: \.self) { columnIndex in
                                        let index = 4 * rowIndex + columnIndex
                                        if index <= thumbnails.count - 1 {
                                            let item = thumbnails[index]
                                            Button(action: {
                                                if !selected.contains(item.window) {
                                                    selected = [item.window]
                                                } else {
                                                    selected.removeAll()
                                                }
                                            }, label: {
                                                VStack(spacing: 1){
                                                    ZStack{
                                                        if colorScheme == .light {
                                                            Image(nsImage: item.image)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fit)
                                                                .colorMultiply(.black)
                                                                .blur(radius: 0.5)
                                                                .opacity(1)
                                                                .frame(width: 160, height: 90, alignment: .center)
                                                        } else {
                                                            Image(nsImage: item.image)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fit)
                                                                .colorMultiply(.black)
                                                                .colorInvert()
                                                                .blur(radius: 0.5)
                                                                .opacity(1)
                                                                .frame(width: 160, height: 90, alignment: .center)
                                                        }
                                                        Image(nsImage: item.image)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fit)
                                                            .frame(width: 160, height: 90, alignment: .center)
                                                        Image(systemName: "circle.fill")
                                                            .font(.system(size: 31))
                                                            .foregroundStyle(.white)
                                                            .opacity(selected.contains(item.window) ? 1.0 : 0.0)
                                                            .offset(x: 55, y: 25)
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.system(size: 27))
                                                            .foregroundStyle(.green)
                                                            .opacity(selected.contains(item.window) ? 1.0 : 0.0)
                                                            .offset(x: 55, y: 25)
                                                        Image(nsImage: getAppIcon(item.window.owningApplication!)!)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fit)
                                                            .frame(width: 40, height: 40, alignment: .center)
                                                            .offset(y: 35)
                                                    }
                                                    .padding(5)
                                                    .padding([.top, .bottom], 5)
                                                    .background(
                                                        Rectangle()
                                                            .foregroundStyle(.blue)
                                                            .cornerRadius(5)
                                                            .opacity(selected.contains(item.window) ? 0.2 : 0.0001)
                                                    )
                                                    Text(item.window.title!)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)
                                                        .frame(width: 160)
                                                }
                                            }).buttonStyle(.plain)
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .tag(index)
                    .tabItem { Text(screen.nsScreen?.localizedName ?? ("Display ".local + "\(index)")) }
                    .onAppear { display = screen }
                }
            }
        }
        .focusable(false)
        .frame(width: 728, height: 500)
        .padding([.horizontal, .bottom], 10)
        .padding(.top, 0.5)
        .padding(.top, isMacOS12 || isMacOS13 ? -20 : 0)
        .background(WindowAccessor(onWindowOpen: { w in panel = w }))
        .onAppear { viewModel.setupStreams(filter: !noTitle) }
        .onChange(of: selectedTab) { _ in selected.removeAll() }
        .onChange(of: noTitle) { newValue in
            if let p = panel, p.isVisible {
                selected.removeAll()
                viewModel.setupStreams(filter: !noTitle)
            }
        }
        .onReceive(viewModel.$isReady) { isReady in
            if isReady {
                let allApps = viewModel.windowThumbnails.sorted(by: { $0.key.displayID < $1.key.displayID })
                if let s = panel?.screen, let index = allApps.firstIndex(where: { $0.key.displayID == s.displayID }) {
                    selectedTab = index
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HoverButton(action: {
                    openSettingPanel()
                }, label: {
                    Image(systemName: "gear").font(.system(size: 14, weight: .medium))
                }).help("Open Settings")
            }
            ToolbarItem(placement: .automatic) {
                HoverButton(action: {
                    selected.removeAll()
                    viewModel.setupStreams(filter: !noTitle)
                }, label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .medium))
                }).help("Update Window List")
            }
            ToolbarItem(placement: .automatic) {
                HoverButton(action: {
                    //panel?.close()
                    WindowHighlighter.shared.registerMouseMonitor()
                }, label: {
                    Image("window.select")
                        .resizable().scaledToFit()
                        .frame(width: 20)
                }).help("Select Window Directly")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    if let window = selected.first, let panel = panel {
                        _ = SCManager.updateAvailableContentSync()
                        if SCManager.getWindows().contains(window) {
                            createNewWindow(display: display, window: window)
                            panel.close()
                        } else {
                            let alert = createAlert(level: .critical, title: "Error", message: "This window is not available!", button1: "OK")
                            alert.beginSheetModal(for: panel) { _ in
                                selected.removeAll()
                                viewModel.setupStreams(filter: noTitle)
                            }
                        }
                    }
                }, label: {
                    Text(" TopitToo! ")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(.white)
                        .background(selected.isEmpty ? Color.secondary.opacity(0.5) : .blue)
                        .cornerRadius(5)
                })
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
            }
        }
    }
}

struct BlurView: NSViewRepresentable {
    private let material: NSVisualEffectView.Material
    
    init(material: NSVisualEffectView.Material) {
        self.material = material
    }
    
    func makeNSView(context: Context) -> some NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.material = material
    }
}
