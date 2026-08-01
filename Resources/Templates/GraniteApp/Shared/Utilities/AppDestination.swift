import Foundation

enum AppDestination: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case home
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .settings:
            "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home:
            "house"
        case .settings:
            "gearshape"
        }
    }
}
