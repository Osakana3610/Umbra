// Calculates derived character values needed during hiring and runtime reloads.

import Foundation

enum CharacterDerivedStatsCalculator {
    private static let maxHPScale = 3.0

    static func maxHP(
        raceId: Int,
        currentJobId: Int,
        level: Int,
        masterData: MasterData
    ) -> Int? {
        guard let race = masterData.races.first(where: { $0.id == raceId }),
              let job = masterData.jobs.first(where: { $0.id == currentJobId }) else {
            return nil
        }

        let baseValue = Int(
            (
                Double(race.baseStats.vitality)
                * Double(level)
                * job.coefficients.maxHP
                * maxHPScale
            )
            .rounded()
        )

        let skillLookup = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        let skillIDs = Set(race.skillIds + job.skillIds)
        var flatSum = 0.0
        var percentSum = 0.0
        var allBattleStatMultiplier = 1.0

        for skillID in skillIDs {
            guard let skill = skillLookup[skillID] else {
                continue
            }

            for effect in skill.effects {
                guard let value = effect.value else {
                    continue
                }

                switch effect.kind {
                case .battleStatModifier:
                    guard effect.target == "maxHP" else {
                        continue
                    }

                    switch effect.operation {
                    case "flatAdd":
                        flatSum += value
                    case "pctAdd":
                        percentSum += value
                    default:
                        break
                    }
                case .allBattleStatMultiplier:
                    switch effect.operation {
                    case "mul":
                        allBattleStatMultiplier *= value
                    case "pctAdd":
                        allBattleStatMultiplier *= 1.0 + value
                    default:
                        break
                    }
                default:
                    continue
                }
            }
        }

        let skillAdjusted = (Double(baseValue) + flatSum) * (1.0 + percentSum)
        return max(Int((skillAdjusted * allBattleStatMultiplier).rounded()), 1)
    }
}
