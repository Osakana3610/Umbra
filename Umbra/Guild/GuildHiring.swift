// Holds the guild hiring rules for pricing and creating new characters.

import Foundation

enum GuildHiring {
    static func price(raceId: Int, jobId: Int, masterData: MasterData) -> Int? {
        guard let race = masterData.races.first(where: { $0.id == raceId }),
              let job = masterData.jobs.first(where: { $0.id == jobId }) else {
            return nil
        }

        // Hiring cost is the race base price scaled by the selected starting job.
        let rawHirePrice = Int((Double(race.baseHirePrice) * job.hirePriceMultiplier).rounded())
        // Hiring shares the same currency ceiling as shop and unlock flows so very expensive
        // combinations still fit in one gold-based economy.
        return min(rawHirePrice, EconomyPricing.maximumEconomicPrice)
    }

    static func makeCharacterRecord(
        nextCharacterId: Int,
        raceId: Int,
        jobId: Int,
        aptitudeId: Int,
        masterData: MasterData
    ) throws -> CharacterRecord {
        guard masterData.races.contains(where: { $0.id == raceId }),
              masterData.jobs.contains(where: { $0.id == jobId }),
              masterData.aptitudes.contains(where: { $0.id == aptitudeId }) else {
            throw GuildServiceError.invalidHireSelection
        }

        let portraitGender = PortraitGender.allCases.randomElement() ?? .unisex
        let name = randomName(
            matching: portraitGender,
            from: masterData.recruitNames
        ) ?? fallbackName(for: portraitGender, nextCharacterId: nextCharacterId)
        // Starting HP is derived through the same runtime stat calculator used elsewhere so new
        // recruits enter the roster with a consistent level-1 baseline.
        let currentHP = CharacterDerivedStatsCalculator.maxHP(
            raceId: raceId,
            currentJobId: jobId,
            level: 1,
            masterData: masterData
        ) ?? 1

        return CharacterRecord(
            characterId: nextCharacterId,
            name: name,
            raceId: raceId,
            previousJobId: 0,
            currentJobId: jobId,
            aptitudeId: aptitudeId,
            portraitGender: portraitGender,
            experience: 0,
            level: 1,
            currentHP: currentHP,
            autoBattleSettings: .default
        )
    }

    private static func randomName(
        matching portraitGender: PortraitGender,
        from recruitNames: MasterData.RecruitNames
    ) -> String? {
        // Name pools stay segmented by portrait gender so generated recruits feel intentional
        // before falling back to synthetic labels.
        switch portraitGender {
        case .male:
            recruitNames.male.randomElement()
        case .female:
            recruitNames.female.randomElement()
        case .unisex:
            recruitNames.unisex.randomElement()
        }
    }

    private static func fallbackName(
        for portraitGender: PortraitGender,
        nextCharacterId: Int
    ) -> String {
        // Fallback names keep recruit generation working even when the source name list is empty.
        switch portraitGender {
        case .male:
            "男性冒険者\(nextCharacterId)"
        case .female:
            "女性冒険者\(nextCharacterId)"
        case .unisex:
            "中性冒険者\(nextCharacterId)"
        }
    }
}
