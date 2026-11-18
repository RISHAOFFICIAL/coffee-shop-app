import Foundation

/// The Stage 3 sync merge rule, written in Sprint 1 so the models and the
/// sync design agree from the start. The network half of sync arrives in
/// Sprint 6; this pure function is the rule it will use.
/// Rule: the same shop on the same calendar date merges into one visit,
/// never a duplicate. When two visits conflict, the version with more
/// joggers filled in wins, and the merge is counted for the confirmation
/// line (for example, "12 visits backed up, 1 duplicate merged").
enum VisitMerge {
    static func key(for visit: Visit, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: visit.checkedInAt)
        return "\(visit.shopID.uuidString)|\(day.timeIntervalSince1970)"
    }

    /// Merges remote visits into local ones. Returns the merged list and
    /// how many duplicates were folded together.
    static func merge(local: [Visit], remote: [Visit], calendar: Calendar = .current) -> (merged: [Visit], duplicatesMerged: Int) {
        var byKey: [String: Visit] = [:]
        var duplicatesMerged = 0
        for visit in local {
            byKey[key(for: visit, calendar: calendar)] = visit
        }
        for visit in remote {
            let mergeKey = key(for: visit, calendar: calendar)
            if let existing = byKey[mergeKey] {
                duplicatesMerged += 1
                if visit.joggerCount > existing.joggerCount {
                    byKey[mergeKey] = visit
                }
            } else {
                byKey[mergeKey] = visit
            }
        }
        let merged = byKey.values.sorted { $0.checkedInAt > $1.checkedInAt }
        return (merged, duplicatesMerged)
    }

    /// The counted confirmation line shown after a sign in sync.
    static func confirmationLine(backedUp: Int, duplicatesMerged: Int) -> String {
        if duplicatesMerged == 0 {
            return "\(backedUp) visits backed up."
        }
        if duplicatesMerged == 1 {
            return "\(backedUp) visits backed up, 1 duplicate merged."
        }
        return "\(backedUp) visits backed up, \(duplicatesMerged) duplicates merged."
    }
}
