// Defines a hired character's persisted values and default auto-battle configuration.

import Foundation

struct CharacterRecord: Identifiable, Equatable, Sendable {
    let characterId: Int
    var name: String
    let raceId: Int
    let previousJobId: Int
    let currentJobId: Int
    let aptitudeId: Int
    let portraitGender: PortraitGender
    var experience: Int
    var level: Int
    var currentHP: Int
    var autoBattleSettings: CharacterAutoBattleSettings

    var id: Int { characterId }

    var portraitAssetName: String {
        "job_\(currentJobId)_\(portraitGender.rawValue)"
    }
}

enum PortraitGender: Int, CaseIterable, Sendable {
    case male = 1
    case female = 2
    case unisex = 3
}

struct CharacterAutoBattleSettings: Equatable, Sendable {
    var rates: CharacterActionRates
    var priority: [BattleActionKind]

    static let `default` = CharacterAutoBattleSettings(
        rates: .default,
        priority: [.breath, .recoverySpell, .attackSpell, .attack]
    )
}

struct CharacterActionRates: Equatable, Sendable {
    var breath: Int
    var attack: Int
    var recoverySpell: Int
    var attackSpell: Int

    static let `default` = CharacterActionRates(
        breath: 50,
        attack: 50,
        recoverySpell: 50,
        attackSpell: 50
    )
}
