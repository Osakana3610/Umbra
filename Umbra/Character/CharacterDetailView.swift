// Presents one guild character's persisted values and fully derived combat status.

import SwiftUI

struct CharacterDetailView: View {
    let characterId: Int
    let masterData: MasterData
    let rosterStore: GuildRosterStore
    let explorationStore: ExplorationStore

    @State private var draftRates = CharacterActionRates.default
    @State private var draftPriority = CharacterAutoBattleSettings.default.priority

    private let skillsByID: [Int: MasterData.Skill]
    private let spellsByID: [Int: MasterData.Spell]
    private let nameResolver: EquipmentDisplayNameResolver

    init(
        characterId: Int,
        masterData: MasterData,
        rosterStore: GuildRosterStore,
        explorationStore: ExplorationStore
    ) {
        self.characterId = characterId
        self.masterData = masterData
        self.rosterStore = rosterStore
        self.explorationStore = explorationStore
        skillsByID = Dictionary(uniqueKeysWithValues: masterData.skills.map { ($0.id, $0) })
        spellsByID = Dictionary(uniqueKeysWithValues: masterData.spells.map { ($0.id, $0) })
        nameResolver = EquipmentDisplayNameResolver(masterData: masterData)
    }

    var body: some View {
        Group {
            if let character {
                CharacterDetailLoadedView(
                    character: character,
                    status: status,
                    summaryText: masterData.characterSummaryText(for: character),
                    hpText: hpText(for: character, status: status),
                    experienceToNextLevelText: experienceToNextLevelText(for: character),
                    skillsByID: skillsByID,
                    spellsByID: spellsByID,
                    nameResolver: nameResolver,
                    rosterStore: rosterStore,
                    explorationStore: explorationStore,
                    masterData: masterData,
                    draftRates: $draftRates,
                    draftPriority: $draftPriority,
                    isMutating: rosterStore.isMutating,
                    onNameChange: { updatedName in
                        rosterStore.renameCharacter(
                            characterId: character.characterId,
                            name: updatedName
                        )
                    },
                    onAutoBattleSettingsChange: { updatedSettings in
                        persistAutoBattleSettings(updatedSettings, current: character.autoBattleSettings)
                    }
                )
                .task(id: character.characterId) {
                    // The draft controls mirror persisted values when navigating between
                    // characters, but local slider edits are preserved while a mutation is in flight.
                    synchronizeDraftValues(with: character)
                }
                .onChange(of: character.autoBattleSettings.rates) { _, newValue in
                    if !rosterStore.isMutating {
                        draftRates = newValue
                    }
                }
                .onChange(of: character.autoBattleSettings.priority) { _, newValue in
                    if !rosterStore.isMutating {
                        draftPriority = newValue
                    }
                }
            } else {
                ContentUnavailableView(
                    "キャラクターが見つかりません",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
            }
        }
    }

    private var character: CharacterRecord? {
        rosterStore.charactersById[characterId]
    }

    private var status: CharacterStatus? {
        guard let character else {
            return nil
        }

        return CharacterDerivedStatsCalculator.status(for: character, masterData: masterData)
    }

    private func hpText(for character: CharacterRecord, status: CharacterStatus?) -> String {
        if let status {
            return "\(character.currentHP)/\(status.maxHP)"
        }

        return "\(character.currentHP)"
    }

    private func experienceToNextLevelText(for character: CharacterRecord) -> String {
        guard let race = masterData.races.first(where: { $0.id == character.raceId }) else {
            return "-"
        }

        // The level cap is race-specific, so "next level" becomes a terminal state once the
        // character reaches the cap even if experience continues to be stored.
        guard character.level < race.levelCap else {
            return "上限到達"
        }

        let nextLevelTotalExperience = CharacterLevelProgression.totalExperience(toReach: character.level + 1)
        return "\(max(nextLevelTotalExperience - character.experience, 0))"
    }

    private func synchronizeDraftValues(with character: CharacterRecord) {
        draftRates = character.autoBattleSettings.rates
        draftPriority = character.autoBattleSettings.priority
    }

    private func persistAutoBattleSettings(
        _ updatedSettings: CharacterAutoBattleSettings,
        current: CharacterAutoBattleSettings
    ) {
        // Avoid firing store mutations for every local state refresh when the effective payload
        // has not changed.
        guard updatedSettings != current else {
            return
        }

        rosterStore.updateAutoBattleSettings(
            characterId: characterId,
            autoBattleSettings: updatedSettings
        )
    }
}

private struct CharacterDetailLoadedView: View {
    let character: CharacterRecord
    let status: CharacterStatus?
    let summaryText: String
    let hpText: String
    let experienceToNextLevelText: String
    let skillsByID: [Int: MasterData.Skill]
    let spellsByID: [Int: MasterData.Spell]
    let nameResolver: EquipmentDisplayNameResolver
    let rosterStore: GuildRosterStore
    let explorationStore: ExplorationStore
    let masterData: MasterData
    @Binding var draftRates: CharacterActionRates
    @Binding var draftPriority: [BattleActionKind]
    let isMutating: Bool
    let onNameChange: (String) -> Void
    let onAutoBattleSettingsChange: (CharacterAutoBattleSettings) -> Void

    @State private var presentedSheet: CharacterDetailSheet?
    @State private var isEditingAutoBattlePriority = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        List {
            Section {
                CharacterDetailHeaderView(
                    character: character,
                    summaryText: summaryText,
                    hpText: hpText,
                    draftName: $draftName,
                    isNameFieldFocused: $isNameFieldFocused,
                    isMutating: isMutating,
                    onCommitName: commitCharacterName
                )
            }

            CharacterBasicInfoSectionView(
                character: character,
                masterData: masterData,
                onShowDetail: { detail in
                    presentedSheet = .basicInfo(detail)
                }
            )

            if !character.hasChangedJob {
                Section {
                    Button(action: presentJobChange) {
                        HStack(spacing: 12) {
                            Text("転職する")
                                .foregroundStyle(.tint)

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            CharacterGrowthSectionView(
                character: character,
                experienceToNextLevelText: experienceToNextLevelText
            )

            if let status {
                CharacterStatusSectionsView(
                    status: status,
                    skillsByID: skillsByID,
                    spellsByID: spellsByID
                )
            } else {
                Section("能力値") {
                    Text("ステータスを計算できません。")
                        .foregroundStyle(.red)
                }
            }

            CharacterEquipmentSectionView(
                character: character,
                nameResolver: nameResolver
            )

            Section {
                ForEach(draftPriority, id: \.self) { actionKind in
                    CharacterAutoBattleRowView(
                        title: actionKind.displayName,
                        value: autoBattleRateBinding(for: actionKind),
                        displayedValue: autoBattleRateValue(for: actionKind),
                        isEnabled: isAutoBattleActionAvailable(actionKind),
                        isMutating: isMutating,
                        onCommit: persistAutoBattleSettings
                    )
                }
                .onMove(perform: autoBattlePriorityMoveAction)
            } header: {
                HStack(spacing: 8) {
                    Text("行動率")

                    Spacer()

                    Button(isEditingAutoBattlePriority ? "完了" : "編集") {
                        isEditingAutoBattlePriority.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                }
            } footer: {
                Text("上から順に判定されます。全ての行動が選ばれなかった場合、自動的に防御が選択されます。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("キャラクター詳細")
        .navigationBarTitleDisplayMode(.inline)
        .environment(
            \.editMode,
            Binding.constant(isEditingAutoBattlePriority ? .active : .inactive)
        )
        .sheet(item: $presentedSheet) { sheet in
            NavigationStack {
                sheetDestination(for: sheet)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") {
                                presentedSheet = nil
                            }
                        }
                }
            }
        }
        .task(id: character.characterId) {
            if draftName.isEmpty {
                draftName = character.name
            }
        }
        .onChange(of: character.name) { _, newValue in
            guard !isNameFieldFocused else {
                return
            }

            draftName = newValue
        }
    }

    private func presentJobChange() {
        presentedSheet = .jobChange
    }

    private func commitCharacterName() {
        let normalizedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            draftName = character.name
            return
        }
        guard normalizedName != character.name else {
            draftName = normalizedName
            return
        }

        // Name edits commit only after trimming so both submit and focus-loss paths normalize the
        // same persisted value.
        draftName = normalizedName
        onNameChange(normalizedName)
    }

    private func persistAutoBattleSettings() {
        onAutoBattleSettingsChange(
            CharacterAutoBattleSettings(
                rates: draftRates,
                priority: draftPriority
            )
        )
    }

    private func moveAutoBattlePriority(
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        // Reordering persists immediately so the battle engine and the visible list cannot drift.
        draftPriority.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persistAutoBattleSettings()
    }

    private var autoBattlePriorityMoveAction: ((IndexSet, Int) -> Void)? {
        guard isEditingAutoBattlePriority else {
            return nil
        }

        return moveAutoBattlePriority
    }

    private func autoBattleRateBinding(for actionKind: BattleActionKind) -> Binding<Double> {
        Binding(
            get: { Double(autoBattleRateValue(for: actionKind)) },
            set: { newValue in
                // The slider works in Double for SwiftUI, but the underlying battle rates are
                // stored as integer percentages.
                let roundedValue = Int(newValue.rounded())
                switch actionKind {
                case .breath:
                    draftRates.breath = roundedValue
                case .attack:
                    draftRates.attack = roundedValue
                case .recoverySpell:
                    draftRates.recoverySpell = roundedValue
                case .attackSpell:
                    draftRates.attackSpell = roundedValue
                }
            }
        )
    }

    private func autoBattleRateValue(for actionKind: BattleActionKind) -> Int {
        switch actionKind {
        case .breath:
            draftRates.breath
        case .attack:
            draftRates.attack
        case .recoverySpell:
            draftRates.recoverySpell
        case .attackSpell:
            draftRates.attackSpell
        }
    }

    private func isAutoBattleActionAvailable(_ actionKind: BattleActionKind) -> Bool {
        switch actionKind {
        case .breath:
            status?.canUseBreath ?? false
        case .attack, .recoverySpell, .attackSpell:
            true
        }
    }

    @ViewBuilder
    private func sheetDestination(for sheet: CharacterDetailSheet) -> some View {
        switch sheet {
        case .jobChange:
            JobChangeView(
                characterId: character.characterId,
                masterData: masterData,
                rosterStore: rosterStore,
                explorationStore: explorationStore
            )
        case .basicInfo(let detail):
            basicInfoDetailDestination(for: detail)
        }
    }

    @ViewBuilder
    private func basicInfoDetailDestination(for detail: CharacterBasicInfoDetail) -> some View {
        switch detail {
        case .race(let race):
            RaceDetailView(race: race, masterData: masterData)
        case .currentJob(let job):
            JobDetailView(job: job, masterData: masterData)
        case .previousJob(let job):
            PreviousJobDetailView(job: job, masterData: masterData)
        case .aptitude(let aptitude):
            AptitudeDetailView(aptitude: aptitude, masterData: masterData)
        }
    }
}

private struct CharacterDetailHeaderView: View {
    let character: CharacterRecord
    let summaryText: String
    let hpText: String
    @Binding var draftName: String
    let isNameFieldFocused: FocusState<Bool>.Binding
    let isMutating: Bool
    let onCommitName: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(character.portraitAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 8) {
                TextField("名前", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused(isNameFieldFocused)
                    .submitLabel(.done)
                    .disabled(isMutating)
                    .onSubmit {
                        onCommitName()
                    }
                    .onChange(of: isNameFieldFocused.wrappedValue) { _, isFocused in
                        guard !isFocused else {
                            return
                        }

                        onCommitName()
                    }
                    .accessibilityLabel("キャラクター名")

                Text(summaryText)

                Text("HP \(hpText)")
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private enum CharacterBasicInfoDetail: Identifiable {
    case race(MasterData.Race)
    case currentJob(MasterData.Job)
    case previousJob(MasterData.Job)
    case aptitude(MasterData.Aptitude)

    var id: String {
        switch self {
        case .race(let race):
            "race-\(race.id)"
        case .currentJob(let job):
            "current-job-\(job.id)"
        case .previousJob(let job):
            "previous-job-\(job.id)"
        case .aptitude(let aptitude):
            "aptitude-\(aptitude.id)"
        }
    }
}

private enum CharacterDetailSheet: Identifiable {
    case jobChange
    case basicInfo(CharacterBasicInfoDetail)

    var id: String {
        switch self {
        case .jobChange:
            "job-change"
        case .basicInfo(let detail):
            "basic-info-\(detail.id)"
        }
    }
}

private struct CharacterBasicInfoSectionView: View {
    let character: CharacterRecord
    let masterData: MasterData
    let onShowDetail: (CharacterBasicInfoDetail) -> Void

    var body: some View {
        Section("基本情報") {
            CharacterBasicInfoRowView(
                title: "種族",
                value: race?.name ?? "不明",
                detailLabel: "\(race?.name ?? "種族")の詳細",
                onShowDetail: race.map { race in
                    { onShowDetail(.race(race)) }
                }
            )
            CharacterBasicInfoRowView(
                title: "現職",
                value: currentJob?.name ?? "不明",
                detailLabel: "\(currentJob?.name ?? "職業")の詳細",
                onShowDetail: currentJob.map { job in
                    { onShowDetail(.currentJob(job)) }
                }
            )
            CharacterBasicInfoRowView(
                title: "前職",
                value: previousJob?.name ?? "なし",
                detailLabel: "\(previousJob?.name ?? "前職")の詳細",
                onShowDetail: previousJob.map { job in
                    { onShowDetail(.previousJob(job)) }
                }
            )
            CharacterBasicInfoRowView(
                title: "資質",
                value: aptitude?.name ?? "不明",
                detailLabel: "\(aptitude?.name ?? "資質")の詳細",
                onShowDetail: aptitude.map { aptitude in
                    { onShowDetail(.aptitude(aptitude)) }
                }
            )
        }
    }

    private var race: MasterData.Race? {
        masterData.races.first(where: { $0.id == character.raceId })
    }

    private var currentJob: MasterData.Job? {
        masterData.jobs.first(where: { $0.id == character.currentJobId })
    }

    private var previousJob: MasterData.Job? {
        // `0` is the sentinel for "no previous job" in persisted character records.
        guard character.previousJobId != 0 else {
            return nil
        }

        return masterData.jobs.first(where: { $0.id == character.previousJobId })
    }

    private var aptitude: MasterData.Aptitude? {
        masterData.aptitudes.first(where: { $0.id == character.aptitudeId })
    }
}

private struct CharacterBasicInfoRowView: View {
    let title: String
    let value: String
    let detailLabel: String
    let onShowDetail: (() -> Void)?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(value)

                if let onShowDetail {
                    Button(action: onShowDetail) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(detailLabel)
                }
            }
        }
    }
}

private struct CharacterGrowthSectionView: View {
    let character: CharacterRecord
    let experienceToNextLevelText: String

    var body: some View {
        Section("成長") {
            LabeledContent("レベル") {
                Text("\(character.level)")
                    .monospacedDigit()
            }
            LabeledContent("経験値") {
                Text("\(character.experience)")
                    .monospacedDigit()
            }
            LabeledContent("次レベルまで") {
                Text(experienceToNextLevelText)
                    .monospacedDigit()
            }
        }
    }
}

private struct CharacterStatusSectionsView: View {
    let status: CharacterStatus
    let skillsByID: [Int: MasterData.Skill]
    let spellsByID: [Int: MasterData.Spell]

    var body: some View {
        Section("基本能力値") {
            ForEach(baseStatRows, id: \.title) { row in
                CharacterStatRowView(title: row.title, value: row.value)
            }
        }

        Section("戦闘能力値") {
            ForEach(battleStatRows, id: \.title) { row in
                CharacterStatRowView(title: row.title, value: row.value)
            }
        }

        Section("戦闘派生") {
            ForEach(derivedStatRows, id: \.title) { row in
                CharacterStatRowView(title: row.title, value: row.value)
            }
        }

        Section("スキル") {
            if status.skillIds.isEmpty {
                Text("なし")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.skillIds.sorted(), id: \.self) { skillID in
                    CharacterSkillRowView(
                        title: skillsByID[skillID]?.name ?? "不明なスキル",
                        description: skillsByID[skillID]?.description
                    )
                }
            }
        }

        Section("使用可能魔法") {
            if status.spellIds.isEmpty {
                Text("なし")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.spellIds.sorted(), id: \.self) { spellID in
                    Text(spellsByID[spellID]?.name ?? "不明な魔法")
                }
            }
        }
    }

    private var baseStatRows: [(title: String, value: String)] {
        [
            ("体力", "\(status.baseStats.vitality)"),
            ("腕力", "\(status.baseStats.strength)"),
            ("精神", "\(status.baseStats.mind)"),
            ("知略", "\(status.baseStats.intelligence)"),
            ("俊敏", "\(status.baseStats.agility)"),
            ("運", "\(status.baseStats.luck)")
        ]
    }

    private var battleStatRows: [(title: String, value: String)] {
        [
            ("最大HP", "\(status.battleStats.maxHP)"),
            ("物理攻撃", "\(status.battleStats.physicalAttack)"),
            ("物理防御", "\(status.battleStats.physicalDefense)"),
            ("魔法攻撃", "\(status.battleStats.magic)"),
            ("魔法防御", "\(status.battleStats.magicDefense)"),
            ("回復", "\(status.battleStats.healing)"),
            ("命中", "\(status.battleStats.accuracy)"),
            ("回避", "\(status.battleStats.evasion)"),
            ("攻撃回数", "\(status.battleStats.attackCount)"),
            ("必殺率", "\(status.battleStats.criticalRate)"),
            ("ブレス威力", "\(status.battleStats.breathPower)")
        ]
    }

    private var derivedStatRows: [(title: String, value: String)] {
        [
            ("物理威力倍率", percentageText(status.battleDerivedStats.physicalDamageMultiplier)),
            ("攻撃魔法威力倍率", percentageText(status.battleDerivedStats.attackMagicMultiplier)),
            ("回復魔法威力倍率", percentageText(status.battleDerivedStats.healingMultiplier)),
            ("個別魔法威力倍率", percentageText(status.battleDerivedStats.spellDamageMultiplier)),
            ("必殺時威力倍率", percentageText(status.battleDerivedStats.criticalDamageMultiplier)),
            ("近接威力倍率", percentageText(status.battleDerivedStats.meleeDamageMultiplier)),
            ("遠距離威力倍率", percentageText(status.battleDerivedStats.rangedDamageMultiplier)),
            ("行動速度倍率", percentageText(status.battleDerivedStats.actionSpeedMultiplier)),
            ("物理被ダメージ倍率", percentageText(status.battleDerivedStats.physicalResistanceMultiplier)),
            ("魔法被ダメージ倍率", percentageText(status.battleDerivedStats.magicResistanceMultiplier)),
            ("ブレス被ダメージ倍率", percentageText(status.battleDerivedStats.breathResistanceMultiplier))
        ]
    }

    private func percentageText(_ value: Double) -> String {
        // Derived multipliers are rendered as whole percentages to match the way battle-facing
        // modifiers are described elsewhere in the UI.
        "\(Int((value * 100).rounded()))%"
    }
}

private struct CharacterEquipmentSectionView: View {
    let character: CharacterRecord
    let nameResolver: EquipmentDisplayNameResolver

    var body: some View {
        Section {
            if character.orderedEquippedItemStacks.isEmpty {
                Text("装備なし")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(character.orderedEquippedItemStacks) { stack in
                    LabeledContent(nameResolver.displayName(for: stack.itemID)) {
                        Text("x\(stack.count)")
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("装備（\(character.equippedItemCount)/\(character.maximumEquippedItemCount)）")
        }
    }
}

private struct CharacterStatRowView: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
        }
    }
}

private struct CharacterSkillRowView: View {
    let title: String
    let description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CharacterAutoBattleRowView: View {
    let title: String
    @Binding var value: Double
    let displayedValue: Int
    let isEnabled: Bool
    let isMutating: Bool
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title)

                Spacer()

                Text("\(displayedValue)%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: 0...100, step: 1) { isEditing in
                if !isEditing {
                    onCommit()
                }
            }
            .disabled(isMutating || !isEnabled)
        }
        .padding(.vertical, 2)
        .foregroundStyle(isEnabled ? .primary : .secondary)
        .opacity(isEnabled ? 1.0 : 0.45)
    }
}

private extension BattleActionKind {
    var displayName: String {
        switch self {
        case .breath:
            "ブレス"
        case .attack:
            "攻撃"
        case .recoverySpell:
            "回復魔法"
        case .attackSpell:
            "攻撃魔法"
        }
    }
}
