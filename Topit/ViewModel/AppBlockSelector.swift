//
//  BundleSelector.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/28.
//

import SwiftUI
import Foundation

struct BundleSelector: View {
    @State private var Bundles = [AppInfo]()
    @State private var isShowingFilePicker = false
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
            List(Bundles, id: \.self) { item in
                HStack{
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .onTapGesture {
                            if let index = Bundles.firstIndex(of: item) {
                                _ = withAnimation { Bundles.remove(at: index) }
                            }
                        }
                    Text(item.displayName).font(.system(size: 12))
                        .help(item.executablePath ?? item.bundleID)
                }
            }
            Button(action: {
                self.isShowingFilePicker = true
            }) {
                Image(systemName: "plus.square.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }.buttonStyle(.plain).offset(y: -1)
        }
        .onAppear {
            if let savedData = ud.data(forKey: "hiddenApps"),
               let decodedApps = try? JSONDecoder().decode([AppInfo].self, from: savedData) {
                Bundles = decodedApps
            }
        }
        .onChange(of: Bundles) { bundles in
            if let encodedData = try? JSONEncoder().encode(bundles) {
                ud.set(encodedData, forKey: "hiddenApps")
            }
        }
        .fileImporter(isPresented: $isShowingFilePicker, allowedContentTypes: [.application, .unixExecutable]) { result in
            do {
                let url = try result.get()
                let bundle = Bundle(url: url)
                let app: AppInfo
                if let bundle = bundle, let appID = bundle.bundleIdentifier {
                    app = AppInfo(bundleID: appID, displayName: bundle.fileName)
                } else {
                    // 未打包的程序没有 bundle ID，按可执行文件路径记录
                    let executable = bundle?.executableURL ?? url
                    app = AppInfo(bundleID: "", displayName: url.lastPathComponent, executablePath: executable.resolvingSymlinksInPath().path)
                }
                if !self.Bundles.contains(app) {
                    withAnimation { Bundles.append(app) }
                }
            } catch {
                print("File selection failed: \(error.localizedDescription)")
            }
        }
    }
}

struct AppInfo: Hashable, Codable {
    let bundleID: String
    let displayName: String
    var executablePath: String? = nil
}

extension Bundle {
    var bundleName: String? { return object(forInfoDictionaryKey: "CFBundleName") as? String }
    var fileName: String { return self.bundleURL.lastPathComponent }
}
