// Owns master-data loading state for the app and exposes reload entry points.

import Foundation
import Observation

@MainActor
@Observable
final class MasterDataLoadStore {
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

        // Master data is replaced atomically at the phase level so dependent views either observe
        // the previous loaded snapshot or the next one, never a partial decode state.
        phase = .loading

        do {
            phase = .loaded(try loader.load())
        } catch {
            phase = .failed(UserFacingErrorMessage.resolve(error))
        }
    }

    private var isLoading: Bool {
        if case .loading = phase {
            return true
        }

        return false
    }

}
