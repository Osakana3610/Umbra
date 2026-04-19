// Defines the user-facing retention presets for completed exploration logs.

import Foundation

nonisolated enum ExplorationLogRetentionLimit: Int, CaseIterable, Identifiable {
    case count200 = 200
    case count300 = 300
    case count400 = 400
    case count500 = 500
    case count600 = 600
    case count700 = 700
    case count800 = 800
    case count900 = 900
    case count1000 = 1_000

    static let defaultValue: Self = .count300

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)件"
    }
}

nonisolated enum ExplorationLogRetentionRepository {
    static let userDefaultsKey = "explorationLogRetentionCount"

    static func configuredCount(
        userDefaults: UserDefaults = .standard
    ) -> Int {
        let configuredCount = userDefaults.object(forKey: userDefaultsKey) as? Int
        return configuredCount.map { max($0, ExplorationLogRetentionLimit.count200.rawValue) }
            ?? ExplorationLogRetentionLimit.defaultValue.rawValue
    }
}
