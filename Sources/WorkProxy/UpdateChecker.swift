import AppKit
import Sparkle
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建"
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        controller.startUpdater()
    }

    func check() {
        start()
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        Button("检查更新…") { checker.check() }
            .disabled(!checker.canCheckForUpdates)
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        HStack {
            Text("当前版本 " + checker.currentVersion).foregroundStyle(.secondary)
            Spacer()
            CheckForUpdatesButton(checker: checker)
        }
        Toggle("自动检查更新", isOn: Binding(
            get: { checker.automaticallyChecksForUpdates },
            set: { checker.setAutomaticallyChecksForUpdates($0) }
        ))
    }
}
