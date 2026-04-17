import Foundation

enum AppGroup {
    static let identifier = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_IDENTIFIER") as? String
        ?? "group.com.eugeniorenna.ytbackground"

    static let defaults = UserDefaults(suiteName: identifier) ?? .standard
}
