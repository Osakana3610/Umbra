// Shares job-change eligibility rules between UI and guild mutations.

import Foundation

extension CharacterRecord {
    var hasChangedJob: Bool {
        previousJobId != 0
    }
}

extension MasterData.Job {
    func canChange(
        fromCurrentJobId currentJobId: Int,
        level: Int
    ) -> Bool {
        let requiredCurrentJobId = jobChangeRequirement?.requiredCurrentJobId ?? 0
        let requiredLevel = jobChangeRequirement?.requiredLevel ?? 0
        let currentJobMatches = requiredCurrentJobId == 0 || requiredCurrentJobId == currentJobId
        return currentJobMatches && level >= requiredLevel
    }

    func jobChangeRequirementSummary(masterData: MasterData) -> String? {
        let requiredCurrentJobId = jobChangeRequirement?.requiredCurrentJobId ?? 0
        let requiredLevel = jobChangeRequirement?.requiredLevel ?? 0
        var parts: [String] = []

        if requiredCurrentJobId != 0 {
            parts.append("現職: \(masterData.jobName(for: requiredCurrentJobId))")
        }
        if requiredLevel > 0 {
            parts.append("Lv.\(requiredLevel)以上")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}
