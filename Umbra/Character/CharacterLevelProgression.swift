// Calculates cumulative experience thresholds and level changes for player characters.

import Foundation

nonisolated enum CharacterLevelProgression {
    static func nextLevelExperience(for level: Int) -> Int {
        10 * level * level * level
    }

    static func totalExperience(toReach level: Int) -> Int {
        let previousLevelSum = (level - 1) * level / 2
        return 10 * previousLevelSum * previousLevelSum
    }

    static func level(
        for experience: Int,
        levelCap: Int
    ) -> Int {
        guard levelCap > 1 else {
            return 1
        }

        var resolvedLevel = 1
        while resolvedLevel < levelCap,
              experience >= totalExperience(toReach: resolvedLevel + 1) {
            resolvedLevel += 1
        }
        return resolvedLevel
    }
}
