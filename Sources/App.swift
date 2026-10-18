import SwiftUI
import AppKit


#if !STUDIO_TEST
@main
struct SpecchioStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var localization = AppLocalization.shared
    var body: some Scene {
        WindowGroup("Specchio Studio") {
            StudioView().frame(minWidth: 1050, minHeight: 720)
                .preferredColorScheme(.dark)
                .environment(\.locale, localization.locale)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandMenu(L("Lingua")) {
                Picker(L("Lingua dell’app"), selection: $localization.preference) {
                    ForEach(AppLanguage.allCases) { language in Text(language.label).tag(language) }
                }
                Divider()
                Text(L("Riavvia l’app per applicare la lingua")).font(.caption)
            }
            CommandGroup(replacing: .help) {
                Button(L("Guida di Specchio Studio")) { NotificationCenter.default.post(name: .showStudioGuide, object: nil) }
                Button(L("Licenze open source")) {
                    if let notice = Bundle.main.url(forResource: "NOTICE", withExtension: "txt", subdirectory: "Licenses") {
                        NSWorkspace.shared.open(notice)
                    }
                }
            }
        }
        Settings { LanguageSettingsView() }
    }
}
#endif

extension Notification.Name { static let showStudioGuide = Notification.Name("showStudioGuide") }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let active = StudioRegistry.shared.models.compactMap(\.value)
        guard active.contains(where: { $0.engine.isRecording || $0.engine.isFinalizing || $0.exporter.isExporting || $0.creatorExporter.isExporting || $0.bugReportBusy }) else { return .terminateNow }
        Task {
            for model in active { await model.shutdown() }
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor final class StudioRegistry {
    static let shared = StudioRegistry()
    struct WeakModel { weak var value: StudioModel? }
    var models: [WeakModel] = []
}
