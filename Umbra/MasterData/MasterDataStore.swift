// Owns master-data loading state for the app and exposes reload entry points.

import Foundation
import Observation

@MainActor
@Observable
final class MasterDataStore {
    enum Phase {
        case idle
        case loading
        case loaded(MasterData)
        case failed(String)
    }

    private let loader: MasterDataLoader
    private(set) var phase: Phase

    init(loader: MasterDataLoader = MasterDataLoader()) {
        self.loader = loader
        self.phase = .idle
    }

    init(phase: Phase, loader: MasterDataLoader = MasterDataLoader()) {
        self.loader = loader
        self.phase = phase
    }

    var masterData: MasterData? {
        guard case let .loaded(masterData) = phase else {
            return nil
        }

        return masterData
    }

    func loadIfNeeded() async {
        switch phase {
        case .idle, .failed:
            await reload()
        case .loading, .loaded:
            return
        }
    }

    func reload() async {
        guard !isLoading else {
            return
        }

        phase = .loading

        do {
            phase = .loaded(try loader.load())
        } catch {
            phase = .failed(Self.errorMessage(for: error))
        }
    }

    private var isLoading: Bool {
        if case .loading = phase {
            return true
        }

        return false
    }

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}
