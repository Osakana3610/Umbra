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
        let repository = GuildRepository(container: PersistenceController(inMemory: true).container)

        let playerState = try repository.loadPlayerState()
        let characters = try repository.loadCharacters()
        let parties = try repository.loadParties()

        #expect(playerState == .initial)
        #expect(characters.isEmpty)
        #expect(parties == [PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [])])
    }

    @Test
    func hireCharacterPersistsPlayerAndCharacterState() async throws {
        let repository = GuildRepository(container: PersistenceController(inMemory: true).container)
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
    func unlockPartyConsumesGoldAndCreatesSequentialParty() async throws {
        let repository = GuildRepository(container: PersistenceController(inMemory: true).container)

        try repository.unlockParty()

        let snapshot = try repository.loadSnapshot()
        #expect(snapshot.playerState.gold == PlayerState.initial.gold - PartyRecord.unlockCost)
        #expect(snapshot.parties == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: []),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [])
        ])
    }

    @Test
    func movingCharacterBetweenPartiesUpdatesMembership() async throws {
        let repository = GuildRepository(container: PersistenceController(inMemory: true).container)
        let masterData = try loadGeneratedMasterData()

        let firstCharacter = try repository.hireCharacter(
            raceId: try #require(masterData.races.first?.id),
            jobId: try #require(masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        let secondCharacter = try repository.hireCharacter(
            raceId: try #require(masterData.races.dropFirst().first?.id ?? masterData.races.first?.id),
            jobId: try #require(masterData.jobs.dropFirst().first?.id ?? masterData.jobs.first?.id),
            aptitudeId: try #require(masterData.aptitudes.dropFirst().first?.id ?? masterData.aptitudes.first?.id),
            masterData: masterData
        ).character

        try repository.unlockParty()
        try repository.addCharacter(characterId: firstCharacter.characterId, toParty: 1)
        try repository.addCharacter(characterId: secondCharacter.characterId, toParty: 1)
        try repository.addCharacter(characterId: firstCharacter.characterId, toParty: 2)

        let snapshot = try repository.loadSnapshot()
        #expect(snapshot.parties == [
            PartyRecord(partyId: 1, name: "パーティ1", memberCharacterIds: [secondCharacter.characterId]),
            PartyRecord(partyId: 2, name: "パーティ2", memberCharacterIds: [firstCharacter.characterId])
        ])
    }

    @Test
    func renamingPartyTrimsWhitespaceAndLength() async throws {
        let repository = GuildRepository(container: PersistenceController(inMemory: true).container)

        try repository.renameParty(
            partyId: 1,
            name: "  これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です  "
        )

        let renamedParty = try #require(repository.loadParties().first)
        #expect(renamedParty.name == String("これはとても長いパーティ名ですこれはとても長いパーティ名ですこれはとても長いパーティ名です".prefix(PartyRecord.maxNameLength)))
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
