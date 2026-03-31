// Represents one labyrinth's unlocked exploration difficulty progression.

import Foundation

struct LabyrinthProgressRecord: Equatable, Sendable, Identifiable {
    let labyrinthId: Int
    var highestUnlockedDifficultyTitleId: Int

    var id: Int { labyrinthId }
}
