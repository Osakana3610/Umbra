// Calculates cumulative experience thresholds and level changes for player characters.

import Foundation

nonisolated enum CharacterLevelProgression {
    private static let experienceScale = 5

    static func totalExperience(toReach level: Int) -> Int {
        // The closed form matches the cumulative sum of the cubic level costs above.
        let previousLevelSum = (level - 1) * level / 2
        return experienceScale * previousLevelSum * previousLevelSum
    }

    static func level(
        for experience: Int,
        levelCap: Int
    ) -> Int {
        guard levelCap > 1 else {
            return 1
        }

        // Character levels are resolved from cumulative experience so loading persisted state never
        // depends on storing level and experience separately in sync.
        var resolvedLevel = 1
        while resolvedLevel < levelCap,
              experience >= totalExperience(toReach: resolvedLevel + 1) {
            resolvedLevel += 1
        }
        return resolvedLevel
    }
}
