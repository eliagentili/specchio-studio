import Foundation

enum LocalizationTests {
    static func run() throws {
        guard Localization.language(preference:nil, preferredLanguages:["it-IT"]) == "en",
              Localization.language(preference:"en", preferredLanguages:["it-IT"]) == "en",
              Localization.language(preference:"it", preferredLanguages:["en-US"]) == "it",
              Localization.language(preference:"system", preferredLanguages:["fr-FR","it-IT"]) == "it",
              Localization.language(preference:"system", preferredLanguages:["de-DE"]) == "en",
              Localization.language(preference:"invalid", preferredLanguages:["it-IT"]) == "en" else {
            fatalError("App language preference or supported-language fallback is incorrect")
        }
        let defaults = UserDefaults.standard
        let savedPreference = defaults.object(forKey: Localization.preferenceKey)
        let runningLanguage = Localization.currentLanguage
        defaults.set(runningLanguage == "en" ? "it" : "en", forKey: Localization.preferenceKey)
        guard Localization.currentLanguage == runningLanguage else {
            fatalError("Changing the next-launch language changed an active interface")
        }
        if let savedPreference { defaults.set(savedPreference, forKey: Localization.preferenceKey) }
        else { defaults.removeObject(forKey: Localization.preferenceKey) }
        let bundle = Localization.resourceBundle
        guard Localization.text("Lingua",language:"en",bundle:bundle) == "Language",
              Localization.text("Lingua",language:"it",bundle:bundle) == "Lingua",
              Localization.text("Portrait 9:16",language:"it",bundle:bundle) == "Verticale 9:16",
              Localization.text("Verticale 9:16",language:"en",bundle:bundle) == "Portrait 9:16",
              Localization.text("Specchio Studio",language:"en",bundle:bundle) == "Specchio Studio" else {
            fatalError("Localized resources or cached-label reverse lookup failed")
        }
        let format = "Esportazione: %@"
        guard Localization.format(format,language:"en",arguments:["sample.mov"]) == "Export: sample.mov",
              Localization.format(format,language:"it",arguments:["sample.mov"]) == "Esportazione: sample.mov" else {
            fatalError("Translated format string lost its dynamic argument")
        }
        let sourceRawValues = CompositionFormat.allCases.map(\.rawValue)
        guard sourceRawValues == ["Automatico","Verticale 9:16","Quadrato 1:1","Orizzontale 16:9"] else {
            fatalError("Localization changed persisted composition format identities")
        }
        for language in ["en","it"] {
            guard let path=bundle.path(forResource:language,ofType:"lproj"),
                  let strings=NSDictionary(contentsOfFile:path+"/Localizable.strings") as? [String:String],
                  let permissionStrings=NSDictionary(contentsOfFile:path+"/InfoPlist.strings") as? [String:String],
                  strings.count > 300,
                  permissionStrings["NSCameraUsageDescription"]?.isEmpty == false,
                  permissionStrings["NSMicrophoneUsageDescription"]?.isEmpty == false,
                  permissionStrings["NSLocalNetworkUsageDescription"]?.isEmpty == false else {
                fatalError("Missing localized interface or system permission resources")
            }
        }
        print("PASS: English/Italian catalogs, persisted identities, formatted messages, language fallback and privacy permission resources")
    }
}
