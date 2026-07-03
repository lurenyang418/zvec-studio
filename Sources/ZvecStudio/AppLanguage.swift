import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .system: "Follow System"
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }
}

struct AppLanguageMenu: View {
    @AppStorage(AppLanguage.defaultsKey) private var appLanguage = AppLanguage.system

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    appLanguage = language
                } label: {
                    if appLanguage == language {
                        Label {
                            Text(language.title)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(language.title)
                    }
                }
            }
        } label: {
            Label {
                Text(appLanguage.title)
            } icon: {
                Image(systemName: "globe")
            }
        }
        .help("Language")
    }
}
