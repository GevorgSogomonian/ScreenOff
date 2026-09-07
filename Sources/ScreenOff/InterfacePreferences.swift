import Combine
import Foundation

@MainActor
final class InterfacePreferences: ObservableObject {
    static let hiddenKey = "hideStatusItem"
    @Published private(set) var statusItemHidden: Bool
    private let preferences: UserDefaults?

    /// Nil storage is used by previews; it never changes the user's settings.
    init(preferences: UserDefaults? = nil) {
        self.preferences = preferences
        statusItemHidden = preferences?.bool(forKey: Self.hiddenKey) ?? false
    }

    func setStatusItemHidden(_ hidden: Bool) {
        statusItemHidden = hidden
        preferences?.set(hidden, forKey: Self.hiddenKey)
    }
}
