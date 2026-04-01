// Stores local item-drop notification filters for title and super-rare item variants.

import Foundation

nonisolated enum ItemDropNotificationSettings {
    private static let showsNormalRarityItemsKey = "itemDropNotification.showsNormalRarityItems"
    private static let titleKeyPrefix = "itemDropNotification.title."
    private static let superRareKeyPrefix = "itemDropNotification.superRare."

    static func showsNormalRarityItems(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: showsNormalRarityItemsKey) as? Bool ?? true
    }

    static func setShowsNormalRarityItems(
        _ isEnabled: Bool,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(isEnabled, forKey: showsNormalRarityItemsKey)
    }

    static func isTitleEnabled(
        _ titleId: Int,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: titleKey(for: titleId)) as? Bool ?? true
    }

    static func setTitleEnabled(
        _ isEnabled: Bool,
        titleId: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(isEnabled, forKey: titleKey(for: titleId))
    }

    static func isSuperRareEnabled(
        _ superRareId: Int,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: superRareKey(for: superRareId)) as? Bool ?? true
    }

    static func setSuperRareEnabled(
        _ isEnabled: Bool,
        superRareId: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(isEnabled, forKey: superRareKey(for: superRareId))
    }

    static func allowsNotification(
        for itemID: CompositeItemID,
        rarity: ItemRarity,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard rarity != .normal || showsNormalRarityItems(userDefaults: userDefaults) else {
            return false
        }

        let titleIDs = Set([itemID.baseTitleId, itemID.jewelTitleId].filter { $0 > 0 })
        let superRareIDs = Set([itemID.baseSuperRareId, itemID.jewelSuperRareId].filter { $0 > 0 })

        return titleIDs.allSatisfy { isTitleEnabled($0, userDefaults: userDefaults) }
            && superRareIDs.allSatisfy { isSuperRareEnabled($0, userDefaults: userDefaults) }
    }

    private static func titleKey(for titleId: Int) -> String {
        "\(titleKeyPrefix)\(titleId)"
    }

    private static func superRareKey(for superRareId: Int) -> String {
        "\(superRareKeyPrefix)\(superRareId)"
    }
}
