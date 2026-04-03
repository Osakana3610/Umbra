// Loads the generated master-data JSON from the app bundle or a file URL.

import Foundation

nonisolated struct MasterDataLoader: Sendable {
    let bundle: Bundle
    let resourceName: String

    init(bundle: Bundle = .main, resourceName: String = "masterdata") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func load() throws -> MasterData {
        guard let fileURL = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw MasterDataLoaderError.missingBundleResource(
                name: resourceName,
                bundlePath: bundle.bundlePath
            )
        }

        // Bundle loading forwards to the file-based loader so tests and tooling can reuse the same
        // decoding and error-reporting path.
        return try Self.load(fileURL: fileURL)
    }

    static func load(fileURL: URL) throws -> MasterData {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw MasterDataLoaderError.unreadableFile(fileURL, underlyingError: error)
        }

        let decodedMasterData: MasterData
        do {
            // Decode the full runtime schema eagerly so format issues fail fast at startup.
            decodedMasterData = try JSONDecoder().decode(MasterData.self, from: data)
        } catch {
            throw MasterDataLoaderError.invalidMasterData(fileURL, underlyingError: error)
        }

        return decodedMasterData
    }
}

nonisolated enum MasterDataLoaderError: LocalizedError {
    case missingBundleResource(name: String, bundlePath: String)
    case unreadableFile(URL, underlyingError: Error)
    case invalidMasterData(URL, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case let .missingBundleResource(name, bundlePath):
            return "バンドル内に \(name).json が見つかりませんでした。bundle=\(bundlePath)"
        case let .unreadableFile(fileURL, underlyingError):
            return "マスターデータを読めませんでした。path=\(fileURL.path) error=\(underlyingError.localizedDescription)"
        case let .invalidMasterData(fileURL, underlyingError):
            return "マスターデータの形式が不正です。path=\(fileURL.path) error=\(underlyingError.localizedDescription)"
        }
    }
}
