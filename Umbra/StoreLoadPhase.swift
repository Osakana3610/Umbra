// Shares load-state handling across the app's domain stores.

import Foundation

enum StoreLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
