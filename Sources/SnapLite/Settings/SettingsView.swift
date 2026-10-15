import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralTab().tabItem { Label("通用", systemImage: "gearshape") }.tag(SettingsTab.general)
            HotkeysTab().tabItem { Label("快捷键", systemImage: "keyboard") }.tag(SettingsTab.hotkeys)
            ScrollingTab().tabItem { Label("长截图", systemImage: "arrow.down.doc") }.tag(SettingsTab.scrolling)
            PermissionsTab().tabItem { Label("权限", systemImage: "lock.shield") }.tag(SettingsTab.permissions)
        }
        .frame(width: 480, height: 400)
    }
}

private struct GeneralTab: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("保存位置", selection: $prefs.saveLocation) {
                ForEach(Preferences.SaveLocation.allCases) { Text($0.title).tag($0) }
            }
            if prefs.saveLocation == .temporary {
                Stepper("保留 \(prefs.tempRetentionDays) 天后自动删除", value: $prefs.tempRetentionDays, in: 1...90)
            } else {
                LabeledContent("文件夹") {
                    HStack {
                        Text(prefs.saveDirectory).truncationMode(.middle).lineLimit(1)
                        Spacer()
                        Button("选择…", action: chooseDirectory)
                    }
                }
            }
            Picker("图片格式", selection: $prefs.format) {
                ForEach(Preferences.Format.allCases) { Text($0.title).tag($0) }
            }
            if prefs.format == .jpg {
                Slider(value: $prefs.jpgQuality, in: 0.5...1.0, step: 0.05) { Text("JPG 质量 \(Int(prefs.jpgQuality * 100))") }
            }
            Toggle("保存到文件", isOn: $prefs.saveToFile)
            Toggle("复制到剪贴板", isOn: $prefs.copyToClipboard)
            Toggle("播放快门音", isOn: $prefs.playSound)
            Toggle("完成后显示预览", isOn: $prefs.showPreview)
            Toggle("登录时启动", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in toggleLogin(on) }
            if let e = loginError {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.saveDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            prefs.saveDirectory = url.path
        }
    }

    private func toggleLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "设置失败：\(error.localizedDescription)（需要以 .app 形式运行）"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct HotkeysTab: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Form {
            row("区域截图", $prefs.regionHotkey)
            row("窗口截图", $prefs.windowHotkey)
            row("全屏截图", $prefs.fullscreenHotkey)
            row("长截图", $prefs.scrollHotkey)
            Text("点击右侧输入框后按下组合键；按退格清除。修改立即生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onChange(of: prefs.regionHotkey) { _, _ in notify() }
        .onChange(of: prefs.windowHotkey) { _, _ in notify() }
        .onChange(of: prefs.fullscreenHotkey) { _, _ in notify() }
        .onChange(of: prefs.scrollHotkey) { _, _ in notify() }
    }

    private func row(_ title: String, _ binding: Binding<Hotkey?>) -> some View {
        LabeledContent(title) { HotkeyRecorder(hotkey: binding).frame(width: 150, height: 24) }
    }

    private func notify() {
        NotificationCenter.default.post(name: .hotkeysChanged, object: nil)
    }
}

private struct ScrollingTab: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Form {
            Stepper("长图最大高度 \(prefs.maxLongHeight) pt", value: $prefs.maxLongHeight, in: 3000...60000, step: 1000)
            Text("框选区域后，在选区内自己向下滚动，每次停下都会自动截帧并拼接；吸顶导航栏、吸底工具条只保留一次。滚动幅度不要超过一屏，保证相邻两帧有重叠。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsTab: View {
    @State private var screen = Permissions.screenRecordingGranted
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            permissionRow("屏幕录制", granted: screen, note: "截图必需。", open: Permissions.openScreenRecordingSettings)
            Text("在系统设置里勾选 SnapLite 后，屏幕录制权限需要重新打开应用才生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            screen = Permissions.screenRecordingGranted
        }
    }

    private func permissionRow(_ title: String, granted: Bool, note: String, open: @escaping () -> Void) -> some View {
        LabeledContent {
            HStack {
                Text(granted ? "已授权" : "未授权").foregroundStyle(granted ? .green : .orange)
                Spacer()
                if !granted { Button("打开系统设置", action: open) }
            }
        } label: {
            VStack(alignment: .leading) {
                Text(title)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
