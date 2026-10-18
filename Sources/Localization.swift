// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case italian = "it"
    case system = "system"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .english: return "English"
        case .italian: return "Italiano"
        case .system: return L("Segui la lingua di macOS")
        }
    }
}

/// Plain strings and background errors use the same catalog as SwiftUI labels.
/// The preference is per app; no capture, model or export is recreated on change.
enum Localization {
    static let preferenceKey = "studio.language"
    static func language(preference: String?, preferredLanguages: [String]) -> String {
        guard preference == AppLanguage.system.rawValue else {
            return preference == AppLanguage.italian.rawValue ? "it" : "en"
        }
        // Match the first supported language, falling back to English.
        for candidate in preferredLanguages {
            let code = candidate.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "it" { return "it" }
            if code == "en" { return "en" }
        }
        return "en"
    }
    // Resolve once per launch: menus, dialogs and cached status messages stay consistent.
    static let currentLanguage: String = {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return language(preference: UserDefaults.standard.string(forKey: preferenceKey),
                        preferredLanguages: global ?? Locale.preferredLanguages)
    }()
    static var resourceBundle: Bundle {
        #if STUDIO_TEST
        // The command-line test runner is not an app bundle. Test the same .lproj files.
        return Bundle(path: FileManager.default.currentDirectoryPath + "/Resources") ?? .main
        #else
        return .main
        #endif
    }
    static func text(_ key: String, language: String, bundle: Bundle = resourceBundle) -> String {
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else { return key }
        return localized.localizedString(forKey: key, value: key, table: "Localizable")
    }
    static func text(_ key: String) -> String { text(key, language: currentLanguage) }
    static func format(_ key: String, language: String, arguments: [CVarArg]) -> String {
        String(format: text(key, language: language), locale: Locale(identifier: language), arguments: arguments)
    }
}

func L(_ key: String) -> String { Localization.text(key) }
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    Localization.format(key, language: Localization.currentLanguage, arguments: arguments)
}

@MainActor final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    @Published var preference: AppLanguage {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Localization.preferenceKey)
            configureSystemLanguage()
        }
    }
    var locale: Locale { Locale(identifier: Localization.currentLanguage) }
    private init() {
        preference = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Localization.preferenceKey) ?? "en") ?? .english
        configureSystemLanguage()
    }
    private func configureSystemLanguage() {
        if preference == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([preference.rawValue], forKey: "AppleLanguages") }
    }
}

struct LanguageSettingsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    var body: some View {
        Form {
            Picker(L("Lingua dell’app"), selection: $localization.preference) {
                ForEach(AppLanguage.allCases) { language in Text(language.label).tag(language) }
            }
            Text(L("Chiudi e riapri l’app per applicare la lingua selezionata. Cambiare questa preferenza non interrompe acquisizioni o esportazioni in corso."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 440)
            .environment(\.locale, localization.locale)
    }
}
