// Verifies runtime master data and guild hiring logic.

import CoreData
import Foundation
import Testing
@testable import Umbra

@MainActor
struct UmbraTests {
    @Test
    func generatedMasterDataDecodes() throws {
        let masterData = try loadGeneratedMasterData()

        #expect(!masterData.races.isEmpty)
        #expect(!masterData.jobs.isEmpty)
        #expect(!masterData.skills.isEmpty)
        #expect(masterData.items.first?.name == "ショートソード")
        #expect(masterData.titles.first(where: { $0.key == "rough" })?.id == 1)
        #expect(masterData.labyrinths.first?.name == "デバッグの洞窟")
    }

    @Test
    func recruitNamesDecodeByGender() throws {
        let masterData = try loadGeneratedMasterData()

        #expect(!masterData.recruitNames.male.isEmpty)
        #expect(!masterData.recruitNames.female.isEmpty)
        #expect(!masterData.recruitNames.unisex.isEmpty)
    }

    @Test
    func guildRepositoryCreatesInitialPlayerState() async throws {
        let container = PersistenceController(inMemory: true).container
        let rosterRepository = GuildRosterRepository(container: container)
        let partyRepository = PartyRepository(container: container)

        let playerState = try rosterRepository.loadPlayerState()
        let characters = try rosterRepository.loadCharacters()
        let parties = try partyRepository.loadParties()

        #expect(playerState == .initial)
        #expect(characters.isEmpty)
        #expect(parties == [PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [])])
    }

    @Test
    func hireCharacterPersistsPlayerAndCharacterState() async throws {
        let repository = GuildRosterRepository(container: PersistenceController(inMemory: true).container)
        let masterData = try loadGeneratedMasterData()

        let result = try repository.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        )

        #expect(result.hireCost == 1)
        #expect(result.playerState.gold == 999)
        #expect(result.playerState.nextCharacterId == 2)
        #expect(result.character.characterId == 1)
        #expect(!result.character.name.isEmpty)
        #expect(matchesRecruitNamePool(character: result.character, masterData: masterData))
        #expect(result.character.level == 1)
        #expect(result.character.currentHP > 0)
        #expect(result.character.autoBattleSettings == .default)

        let reloadedPlayerState = try repository.loadPlayerState()
        let reloadedCharacters = try repository.loadCharacters()
        #expect(reloadedPlayerState == result.playerState)
        #expect(reloadedCharacters == [result.character])
    }

    @Test
    func completeStatusCalculationBuildsBattleStatsAndCapabilities() throws {
        let masterData = try loadGeneratedMasterData()
        let character = CharacterRecord(
            characterId: 1,
            name: "テスト騎士",
            raceId: try raceId(named: "人間", in: masterData),
            previousJobId: 0,
            currentJobId: try jobId(named: "騎士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            portraitGender: .male,
            experience: 0,
            level: 10,
            currentHP: 1,
            autoBattleSettings: .default
        )

        let status = try #require(CharacterDerivedStatsCalculator.status(for: character, masterData: masterData))

        #expect(status.baseStats == CharacterBaseStats(
            vitality: 7,
            strength: 7,
            mind: 7,
            intelligence: 7,
            agility: 7,
            luck: 7
        ))
        #expect(status.battleStats == CharacterBattleStats(
            maxHP: 231,
            physicalAttack: 42,
            physicalDefense: 23,
            magic: 42,
            magicDefense: 21,
            healing: 32,
            accuracy: 8,
            evasion: 7,
            attackCount: 1,
            criticalRate: 1,
            breathPower: 42
        ))
        #expect(status.battleDerivedStats == .baseline)
        #expect(status.canUseBreath == false)
        #expect(status.spellIds.isEmpty)
        #expect(status.interruptKinds == [.counter])
        #expect(status.skillIds.count == Set(status.skillIds).count)
    }

    @Test
    func completeStatusCalculationCollectsDerivedEffectsAndSpells() throws {
        let masterData = try loadGeneratedMasterData()
        let spellcastingCharacter = CharacterRecord(
            characterId: 1,
            name: "テスト魔導士",
            raceId: try raceId(named: "サイキック", in: masterData),
            previousJobId: 0,
            currentJobId: try jobId(named: "魔導士", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            portraitGender: .male,
            experience: 0,
            level: 10,
            currentHP: 1,
            autoBattleSettings: .default
        )
        let breathCharacter = CharacterRecord(
            characterId: 2,
            name: "テスト狩人",
            raceId: try raceId(named: "ドラゴニュート", in: masterData),
            previousJobId: 0,
            currentJobId: try jobId(named: "狩人", in: masterData),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            portraitGender: .female,
            experience: 0,
            level: 10,
            currentHP: 1,
            autoBattleSettings: .default
        )

        let spellcastingStatus = try #require(
            CharacterDerivedStatsCalculator.status(for: spellcastingCharacter, masterData: masterData)
        )
        let breathStatus = try #require(
            CharacterDerivedStatsCalculator.status(for: breathCharacter, masterData: masterData)
        )

        #expect(Set(spellcastingStatus.spellIds) == Set(try spellIds(
            named: ["炎", "氷", "攻撃バフ", "電撃", "魔法バフ", "核攻撃"],
            in: masterData
        )))
        #expect(spellcastingStatus.battleStats.magic == 99)
        #expect(spellcastingStatus.skillIds.count == Set(spellcastingStatus.skillIds).count)

        #expect(breathStatus.canUseBreath)
        #expect(breathStatus.interruptKinds == [.pursuit])
        #expect(breathStatus.battleStats.breathPower == 59)
        #expect(breathStatus.battleDerivedStats == CharacterBattleDerivedStats(
            physicalDamageMultiplier: 1.0,
            magicDamageMultiplier: 1.0,
            spellDamageMultiplier: 1.0,
            criticalDamageMultiplier: 1.0,
            meleeDamageMultiplier: 1.0,
            rangedDamageMultiplier: 1.1,
            actionSpeedMultiplier: 1.1,
            physicalResistanceMultiplier: 1.0,
            magicResistanceMultiplier: 1.0,
            breathResistanceMultiplier: 0.8
        ))
    }

    @Test
    func unlockPartyConsumesGoldAndCreatesSequentialParty() async throws {
        let container = PersistenceController(inMemory: true).container
        let rosterRepository = GuildRosterRepository(container: container)
        let partyRepository = PartyRepository(container: container)

        try partyRepository.unlockParty()

        #expect(try rosterRepository.loadPlayerState().gold == PlayerState.initial.gold - PartyRecord.unlockCost)
        #expect(try partyRepository.loadParties() == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: []),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [])
        ])
    }

    @Test
    func movingCharacterBetweenPartiesUpdatesMembership() async throws {
        let container = PersistenceController(inMemory: true).container
        let rosterRepository = GuildRosterRepository(container: container)
        let partyRepository = PartyRepository(container: container)
        let masterData = try loadGeneratedMasterData()

        let firstCharacter = try rosterRepository.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let secondCharacter = try rosterRepository.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        try partyRepository.unlockParty()
        try partyRepository.addCharacter(characterId: firstCharacter.characterId, toParty: 1)
        try partyRepository.addCharacter(characterId: secondCharacter.characterId, toParty: 1)
        try partyRepository.addCharacter(characterId: firstCharacter.characterId, toParty: 2)

        #expect(try partyRepository.loadParties() == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [secondCharacter.characterId]),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [firstCharacter.characterId])
        ])
    }

    @Test
    func renamingPartyTrimsWhitespaceAndLength() async throws {
        let repository = PartyRepository(container: PersistenceController(inMemory: true).container)

        try repository.renameParty(
            partyId: 1,
            name: "  これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です  "
        )

        let renamedParty = try #require(repository.loadParties().first)
        #expect(renamedParty.name == String("これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です".prefix(PartyRecord.maxNameLength)))
    }

    @Test
    func equippingAndUnequippingUpdatesInventoryAndCharacterStacks() throws {
        let container = PersistenceController(inMemory: true).container
        let rosterRepository = GuildRosterRepository(container: container)
        let equipmentRepository = EquipmentRepository(container: container)
        let masterData = try loadGeneratedMasterData()

        let character = try rosterRepository.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character
        let itemID = CompositeItemID.baseItem(itemId: try #require(masterData.items.first?.id))

        try equipmentRepository.addInventoryStacks(
            [CompositeItemStack(itemID: itemID, count: 2)],
            masterData: masterData
        )

        let equippedCharacter = try equipmentRepository.equip(
            itemID: itemID,
            toCharacter: character.characterId,
            masterData: masterData
        )
        #expect(equippedCharacter.equippedItemStacks == [CompositeItemStack(itemID: itemID, count: 1)])
        #expect(try equipmentRepository.loadInventoryStacks() == [CompositeItemStack(itemID: itemID, count: 1)])

        let unequippedCharacter = try equipmentRepository.unequip(
            itemID: itemID,
            fromCharacter: character.characterId,
            masterData: masterData
        )
        #expect(unequippedCharacter.equippedItemStacks.isEmpty)
        #expect(try equipmentRepository.loadInventoryStacks() == [CompositeItemStack(itemID: itemID, count: 2)])
    }

}

@MainActor
private func matchesRecruitNamePool(character: CharacterRecord, masterData: MasterData) -> Bool {
    switch character.portraitGender {
    case .male:
        masterData.recruitNames.male.contains(character.name)
    case .female:
        masterData.recruitNames.female.contains(character.name)
    case .unisex:
        masterData.recruitNames.unisex.contains(character.name)
    }
}

private func loadGeneratedMasterData() throws -> MasterData {
    if let testHostPath = ProcessInfo.processInfo.environment["TEST_HOST"] {
        let hostBundleURL = URL(fileURLWithPath: testHostPath).deletingLastPathComponent()
        if let hostBundle = Bundle(url: hostBundleURL),
           let fileURL = hostBundle.url(forResource: "masterdata", withExtension: "json") {
            return try MasterDataLoader.load(fileURL: fileURL)
        }
    }

    for bundle in [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks {
        if let fileURL = bundle.url(forResource: "masterdata", withExtension: "json") {
            return try MasterDataLoader.load(fileURL: fileURL)
        }
    }

    let fileURL = generatedMasterDataURL()
    return try MasterDataLoader.load(fileURL: fileURL)
}

private func generatedMasterDataURL() -> URL {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot = testsDirectory.deletingLastPathComponent()
    return repositoryRoot.appending(path: "Generator/Output/masterdata.json")
}

@MainActor
private func raceId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.races.first(where: { $0.name == name })?.id)
}

@MainActor
private func jobId(named name: String, in masterData: MasterData) throws -> Int {
    try #require(masterData.jobs.first(where: { $0.name == name })?.id)
}

@MainActor
private func spellIds(named names: [String], in masterData: MasterData) throws -> [Int] {
    try names.map { name in
        try #require(masterData.spells.first(where: { $0.name == name })?.id)
    }
}
