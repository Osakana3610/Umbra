// Verifies that generated runtime master data decodes and exposes stable lookups.

import Foundation
import Testing
@testable import Umbra

@MainActor
struct UmbraTests {
    @Test
    func generatedMasterDataDecodes() throws {
        let masterData = try MasterDataLoader.load(fileURL: generatedMasterDataURL())

        #expect(!masterData.races.isEmpty)
        #expect(!masterData.jobs.isEmpty)
        #expect(!masterData.skills.isEmpty)
        #expect(masterData.items.first?.name == "ショートソード")
        #expect(masterData.titles.first(where: { $0.key == "rough" })?.id == 1)
        #expect(masterData.labyrinths.first?.name == "デバッグの洞窟")
    }

    @Test
    func namePoolsDecodeInSourceOrder() throws {
        let masterData = try MasterDataLoader.load(fileURL: generatedMasterDataURL())

        #expect(masterData.namePools.count == 3)
        #expect(!masterData.namePools[0].isEmpty)
        #expect(!masterData.namePools[1].isEmpty)
        #expect(masterData.namePools.reduce(0) { $0 + $1.count } > 0)
    }
}

private func generatedMasterDataURL() -> URL {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot = testsDirectory.deletingLastPathComponent()
    return repositoryRoot.appending(path: "Generator/Output/masterdata.json")
}
