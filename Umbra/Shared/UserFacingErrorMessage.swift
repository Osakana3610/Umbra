// Formats errors into the user-facing strings shown by the observable stores.

import Foundation

enum UserFacingErrorMessage {
    static func resolve(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}
