// Presents a debug-only gallery of race icons and job portraits for asset verification.
// The screen intentionally shows only assets that currently resolve in the app bundle so missing job
// portraits stand out immediately while keeping the gallery compact.

import SwiftUI

struct DebugCharacterImageGalleryView: View {
    fileprivate static let gridColumns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    let masterData: MasterData

    private var raceEntries: [DebugCharacterImageEntry] {
        masterData.races.map { race in
            DebugCharacterImageEntry(
                id: "race-\(race.id)",
                assetName: race.assetName,
                title: race.name,
                subtitle: "種族"
            )
        }
    }

    private var jobEntries: [DebugCharacterImageEntry] {
        masterData.jobs.flatMap { job in
            PortraitGender.allCases.compactMap { gender in
                let assetName = job.portraitAssetName(for: gender)
                // Skip unresolved assets so the debug gallery highlights only real bundle entries and
                // does not flood the layout with placeholder cards.
                guard UIImage(named: assetName) != nil else {
                    return nil
                }

                return DebugCharacterImageEntry(
                    id: "job-\(job.id)-\(gender.rawValue)",
                    assetName: assetName,
                    title: job.name,
                    subtitle: gender.displayName
                )
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DebugCharacterImageSectionView(
                    title: "種族",
                    entries: raceEntries
                )
                DebugCharacterImageSectionView(
                    title: "職業",
                    entries: jobEntries
                )
            }
            .padding(16)
        }
    }
}

private struct DebugCharacterImageSectionView: View {
    let title: String
    let entries: [DebugCharacterImageEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            LazyVGrid(columns: DebugCharacterImageGalleryView.gridColumns, spacing: 16) {
                ForEach(entries) { entry in
                    DebugCharacterImageCardView(entry: entry)
                }
            }
        }
    }
}

private struct DebugCharacterImageCardView: View {
    let entry: DebugCharacterImageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if UIImage(named: entry.assetName) != nil {
                GameAssetImage(assetName: entry.assetName, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .padding(.vertical, 8)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }

            Text(entry.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)

            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct DebugCharacterImageEntry: Identifiable {
    let id: String
    let assetName: String
    let title: String
    let subtitle: String?
}

private extension PortraitGender {
    var displayName: String {
        switch self {
        case .male:
            "男性"
        case .female:
            "女性"
        case .unisex:
            "共通"
        }
    }
}
