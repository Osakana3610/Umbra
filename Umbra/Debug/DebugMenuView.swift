// Hosts debug-only inventory generation controls for large equipment test datasets.

import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct DebugMenuView: View {
    private static let debugGoldIncrement = 99_999_999
    private static let fullPartyMemberCount = PartyRecord.maxPartyCount * PartyRecord.memberLimit

    let masterData: MasterData
    let persistentContainer: NSPersistentContainer
    let inventoryService: InventoryManagementService
    let equipmentStore: EquipmentInventoryStore

    @State private var combinationCountPreset: DebugCombinationCountPreset = .tenThousand
    @State private var customCombinationCountText = ""
    @State private var stackCountPreset: DebugStackCountPreset = .one
    @State private var customStackCountText = ""
    @State private var isCreatingRandomCharacter = false
    @State private var isConfiguringRandomParties = false
    @State private var isGenerating = false
    @State private var isPreparingExport = false
    @State private var isExportingUserData = false
    @State private var isDeletingAllData = false
    @State private var isDeleteAllDataConfirmationPresented = false
    @State private var exportDocument: DebugUserDataDocument?
    @State private var exportFilename = ""
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private var generator: DebugItemBatchGenerator {
        DebugItemBatchGenerator(masterData: masterData)
    }

    private var userDataExporter: DebugUserDataExporter {
        DebugUserDataExporter(
            container: persistentContainer,
            masterData: masterData
        )
    }

    private var guildCoreDataRepository: GuildCoreDataRepository {
        GuildCoreDataRepository(container: persistentContainer)
    }

    private var explorationCoreDataRepository: ExplorationCoreDataRepository {
        ExplorationCoreDataRepository(container: persistentContainer)
    }

    private var isBusy: Bool {
        isCreatingRandomCharacter
            || isConfiguringRandomParties
            || isGenerating
            || isPreparingExport
            || isDeletingAllData
    }

    var body: some View {
        Form {
            Section("ユーザーデータ") {
                Button {
                    Task {
                        await exportUserData()
                    }
                } label: {
                    if isPreparingExport {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("出力を準備中...")
                        }
                    } else {
                        Text("ユーザーデータを書き出し")
                    }
                }
                .disabled(isBusy)

                Text("現在の所持金、キャラクター、編成、装備、探索状態を JSON で出力します。")
                    .foregroundStyle(.secondary)
            }

            Section("プレイヤー") {
                Button {
                    Task {
                        await addDebugGold()
                    }
                } label: {
                    Text("\(Self.debugGoldIncrement.formatted())Gを追加")
                }
                .disabled(isBusy)

                Text("所持金に \(Self.debugGoldIncrement.formatted())G を加算します。")
                    .foregroundStyle(.secondary)
            }

            Section("キャラクター・パーティ") {
                Button {
                    Task {
                        await createRandomCharacter()
                    }
                } label: {
                    if isCreatingRandomCharacter {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("ランダム作成中...")
                        }
                    } else {
                        Text("キャラクターをランダム作成")
                    }
                }
                .disabled(isBusy)

                Button {
                    Task {
                        await unlockAndConfigureRandomParties()
                    }
                } label: {
                    if isConfiguringRandomParties {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("パーティ設定中...")
                        }
                    } else {
                        Text("全パーティを解放してランダム編成")
                    }
                }
                .disabled(isBusy)

                Text("全パーティ解放では不足人数ぶんのキャラクターを自動作成し、各パーティを6人でランダム編成して、出撃先を現在解放済みの最新迷宮に揃えます。")
                    .foregroundStyle(.secondary)
            }

            Section("画像確認") {
                NavigationLink("キャラ画像一覧") {
                    DebugCharacterImageGalleryView(masterData: masterData)
                        .navigationTitle("キャラ画像")
                }
            }

            Section("生成対象") {
                Text("称号のみ → 超レア+称号 → 超レア+称号+宝石強化 の順で生成します。")
                    .foregroundStyle(.secondary)
                Text("要求件数に足りない場合は次のグループへ進み、全組み合わせを使い切ったらそこで終了します。")
                    .foregroundStyle(.secondary)
            }

            Section("組み合わせ数") {
                Picker("組み合わせ数", selection: $combinationCountPreset) {
                    ForEach(DebugCombinationCountPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                if combinationCountPreset == .custom {
                    TextField("任意件数", text: $customCombinationCountText)
                        .keyboardType(.numberPad)
                }
            }

            Section("スタック数") {
                Picker("スタック数", selection: $stackCountPreset) {
                    ForEach(DebugStackCountPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                if stackCountPreset == .custom {
                    TextField("任意スタック数", text: $customStackCountText)
                        .keyboardType(.numberPad)
                }
            }

            Section("候補数") {
                Text("称号のみ: \(generator.titleOnlyCombinationCount.formatted()) 件")
                Text("超レア+称号: \(generator.superRareAndTitleCombinationCount.formatted()) 件")
                Text("超レア+称号+宝石強化: \(generator.jewelEnhancedCombinationCount.formatted()) 件")
                Text("合計: \(generator.totalCombinationCount.formatted()) 件")
                    .fontWeight(.semibold)
            }

            Section {
                Button {
                    Task {
                        await generateInventory()
                    }
                } label: {
                    if isGenerating {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("生成中...")
                        }
                    } else {
                        Text("デバッグ用アイテムを生成")
                    }
                }
                .disabled(isBusy)
            }

            if let resultMessage {
                Section("結果") {
                    Text(resultMessage)
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section("エラー") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    isDeleteAllDataConfirmationPresented = true
                } label: {
                    if isDeletingAllData {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("全てのデータを削除中...")
                        }
                    } else {
                        Text("全てのデータを削除")
                    }
                }
                .disabled(isBusy)
            } footer: {
                Text("Core Data ストアを削除したあと、アプリを終了します。")
            }
        }
        .fileExporter(
            isPresented: $isExportingUserData,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                resultMessage = "ユーザーデータを書き出しました。"
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("全てのデータを削除しますか？", isPresented: $isDeleteAllDataConfirmationPresented) {
            Button("削除して終了", role: .destructive) {
                Task {
                    await deleteAllDataAndExit()
                }
            }
            Button("キャンセル", role: .cancel) {
            }
        } message: {
            Text("所持金、キャラクター、編成、装備、探索ログを含む保存データを削除し、アプリを終了します。")
        }
    }

    private func generateInventory() async {
        guard !isGenerating else {
            return
        }

        isGenerating = true
        resultMessage = nil
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let requestedCombinationCount = try resolvedCombinationCount()
            let stackCount = try resolvedStackCount()
            // Generation walks the predefined rarity buckets in order so smaller requests fill from
            // simpler combinations before moving on to super-rare and jewel-enhanced variants.
            let batch = generator.generate(
                requestedCombinationCount: requestedCombinationCount,
                stackCount: stackCount
            )

            guard batch.generatedCombinationCount > 0 else {
                resultMessage = "生成可能な組み合わせがありませんでした。"
                return
            }

            try inventoryService.addInventoryStacks(batch.inventoryStacks, masterData: masterData)
            if equipmentStore.isLoaded {
                equipmentStore.applyInventoryChanges(
                    Dictionary(
                        batch.inventoryStacks.map { ($0.itemID, $0.count) },
                        uniquingKeysWith: +
                    ),
                    masterData: masterData
                )
            }

            let generatedItemCount = batch.generatedCombinationCount * stackCount
            if batch.generatedCombinationCount < requestedCombinationCount {
                resultMessage = "\(batch.generatedCombinationCount.formatted()) 件の組み合わせを生成しました。要求 \(requestedCombinationCount.formatted()) 件に対し、生成可能な全組み合わせを使い切りました。総追加数は \(generatedItemCount.formatted()) 個です。"
            } else {
                resultMessage = "\(batch.generatedCombinationCount.formatted()) 件の組み合わせを生成しました。総追加数は \(generatedItemCount.formatted()) 個です。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedCombinationCount() throws -> Int {
        try combinationCountPreset.resolveValue(customText: customCombinationCountText)
    }

    private func resolvedStackCount() throws -> Int {
        try stackCountPreset.resolveValue(customText: customStackCountText)
    }

    private func exportUserData() async {
        guard !isPreparingExport else {
            return
        }

        isPreparingExport = true
        resultMessage = nil
        errorMessage = nil
        defer { isPreparingExport = false }

        do {
            // Prepare the payload before presenting the exporter so the sheet always opens with a
            // concrete document and filename.
            exportDocument = try await userDataExporter.makeDocument()
            exportFilename = exportFileName
            isExportingUserData = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addDebugGold() async {
        resultMessage = nil
        errorMessage = nil

        do {
            var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
            snapshot.playerState.gold += Self.debugGoldIncrement
            try guildCoreDataRepository.saveRosterSnapshot(snapshot)
            resultMessage = "\(Self.debugGoldIncrement.formatted())G を追加しました。現在 \(snapshot.playerState.gold.formatted())G です。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createRandomCharacter() async {
        guard !isCreatingRandomCharacter else {
            return
        }

        isCreatingRandomCharacter = true
        resultMessage = nil
        errorMessage = nil
        defer { isCreatingRandomCharacter = false }

        do {
            var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
            let character = try makeRandomCharacter(nextCharacterId: snapshot.playerState.nextCharacterId)
            snapshot.playerState.nextCharacterId += 1
            snapshot.characters.append(character)
            try guildCoreDataRepository.saveRosterSnapshot(snapshot)

            let raceName = masterData.race(for: character.raceId)?.name ?? "不明"
            let jobName = masterData.job(for: character.currentJobId)?.name ?? "不明"
            let aptitudeName = masterData.aptitudes.first(where: { $0.id == character.aptitudeId })?.name ?? "不明"
            resultMessage = "\(character.name)を作成しました。\(raceName) / \(jobName) / \(aptitudeName)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unlockAndConfigureRandomParties() async {
        guard !isConfiguringRandomParties else {
            return
        }

        isConfiguringRandomParties = true
        resultMessage = nil
        errorMessage = nil
        defer { isConfiguringRandomParties = false }

        do {
            try await ensureNoActiveRuns()

            var snapshot = try guildCoreDataRepository.loadRosterSnapshot()
            var parties = try guildCoreDataRepository.loadParties()
            var createdCharacterCount = 0

            while parties.count < PartyRecord.maxPartyCount {
                let nextPartyId = parties.count + 1
                parties.append(
                    PartyRecord(
                        partyId: nextPartyId,
                        name: PartyRecord.defaultName(for: nextPartyId),
                        memberCharacterIds: [],
                        selectedLabyrinthId: nil,
                        selectedDifficultyTitleId: nil,
                        automaticallyUsesCatTicket: false
                    )
                )
            }

            if snapshot.characters.count < Self.fullPartyMemberCount {
                let additionalCharacterCount = Self.fullPartyMemberCount - snapshot.characters.count
                for _ in 0..<additionalCharacterCount {
                    let character = try makeRandomCharacter(nextCharacterId: snapshot.playerState.nextCharacterId)
                    snapshot.playerState.nextCharacterId += 1
                    snapshot.characters.append(character)
                }
                createdCharacterCount = additionalCharacterCount
            }

            let sortieDestination = try latestUnlockedSortieDestination(
                labyrinthProgressRecords: snapshot.labyrinthProgressRecords
            )
            let shuffledCharacterIds = snapshot.characters.map(\.characterId).shuffled()

            for partyIndex in parties.indices {
                let startIndex = partyIndex * PartyRecord.memberLimit
                let endIndex = startIndex + PartyRecord.memberLimit
                parties[partyIndex].memberCharacterIds = Array(shuffledCharacterIds[startIndex..<endIndex])
                parties[partyIndex].selectedLabyrinthId = sortieDestination.labyrinthId
                parties[partyIndex].selectedDifficultyTitleId = sortieDestination.selectedDifficultyTitleId
                parties[partyIndex].pendingAutomaticRunCount = 0
                parties[partyIndex].pendingAutomaticRunStartedAt = nil
            }

            try guildCoreDataRepository.saveRosterState(
                snapshot,
                parties: parties,
                inventoryStacks: try guildCoreDataRepository.loadInventoryStacks()
            )

            resultMessage = "\(createdCharacterCount.formatted())人を追加し、\(PartyRecord.maxPartyCount)パーティを全解放して各\(PartyRecord.memberLimit)人をランダム編成しました。出撃先は\(sortieDestination.labyrinthName)です。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeRandomCharacter(nextCharacterId: Int) throws -> CharacterRecord {
        guard let raceId = masterData.races.randomElement()?.id,
              let jobId = masterData.jobs.randomElement()?.id,
              let aptitudeId = masterData.aptitudes.randomElement()?.id else {
            throw DebugMenuMutationError.missingCharacterMasterData
        }

        return try GuildHiring.makeCharacterRecord(
            nextCharacterId: nextCharacterId,
            raceId: raceId,
            jobId: jobId,
            aptitudeId: aptitudeId,
            masterData: masterData
        )
    }

    private func ensureNoActiveRuns() async throws {
        let snapshot = try await explorationCoreDataRepository.loadSnapshot()
        guard snapshot.runs.allSatisfy(\.isCompleted) else {
            throw DebugMenuMutationError.activeRunExists
        }
    }

    private func latestUnlockedSortieDestination(
        labyrinthProgressRecords: [LabyrinthProgressRecord]
    ) throws -> DebugSortieDestination {
        guard let defaultLabyrinthId = masterData.defaultUnlockedLabyrinthId else {
            throw DebugMenuMutationError.missingLabyrinthMasterData
        }

        let unlockedLabyrinthIds = Set(labyrinthProgressRecords.map(\.labyrinthId)).union([defaultLabyrinthId])
        guard let labyrinth = masterData.labyrinths.last(where: { unlockedLabyrinthIds.contains($0.id) }) else {
            throw DebugMenuMutationError.missingLabyrinthMasterData
        }

        let highestUnlockedTitleId = labyrinthProgressRecords.first(where: { $0.labyrinthId == labyrinth.id })?
            .highestUnlockedDifficultyTitleId
        let selectedDifficultyTitleId = masterData.resolvedExplorationDifficultyTitleId(
            requestedTitleId: highestUnlockedTitleId,
            highestUnlockedTitleId: highestUnlockedTitleId
        )

        return DebugSortieDestination(
            labyrinthId: labyrinth.id,
            labyrinthName: labyrinth.name,
            selectedDifficultyTitleId: selectedDifficultyTitleId
        )
    }

    private func deleteAllDataAndExit() async {
        guard !isDeletingAllData else {
            return
        }

        isDeletingAllData = true
        resultMessage = nil
        errorMessage = nil

        do {
            try deletePersistentStores()
            exit(0)
        } catch {
            isDeletingAllData = false
            errorMessage = error.localizedDescription
        }
    }

    private func deletePersistentStores() throws {
        let viewContext = persistentContainer.viewContext
        viewContext.performAndWait {
            viewContext.reset()
        }

        let coordinator = persistentContainer.persistentStoreCoordinator
        for store in Array(coordinator.persistentStores) {
            guard let storeURL = store.url else {
                continue
            }

            try coordinator.destroyPersistentStore(
                at: storeURL,
                type: NSPersistentStore.StoreType(rawValue: store.type),
                options: nil
            )
        }
    }

    private var exportFileName: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        // Keep ISO 8601 ordering while avoiding ":" so the suggested filename stays portable.
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "UmbraUserData-\(timestamp)"
    }
}

private struct DebugSortieDestination {
    let labyrinthId: Int
    let labyrinthName: String
    let selectedDifficultyTitleId: Int
}

private enum DebugMenuMutationError: LocalizedError {
    case missingCharacterMasterData
    case missingLabyrinthMasterData
    case activeRunExists

    var errorDescription: String? {
        switch self {
        case .missingCharacterMasterData:
            "キャラクター作成に必要なマスターデータが不足しています。"
        case .missingLabyrinthMasterData:
            "迷宮設定に必要なマスターデータが不足しています。"
        case .activeRunExists:
            "出撃中のパーティがあるため、全パーティのランダム編成はできません。"
        }
    }
}
