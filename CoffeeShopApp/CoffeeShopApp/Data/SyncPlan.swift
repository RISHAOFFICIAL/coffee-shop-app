import Foundation

/// The pure merge plans for a sync run (Sprint 6, Story S14). Each plan
/// takes the local rows and the downloaded rows and says exactly what to
/// upload, what to insert locally, what to replace, and what to delete,
/// so SyncManager applies the plan without deciding anything itself.
/// These functions touch no network and no database, which is what
/// makes them unit testable. The visit plan reuses the Stage 3 merge
/// rule in VisitMerge: same shop on the same date merges into one visit,
/// never a duplicate, and the version with more joggers wins.
enum SyncPlan {

    // MARK: - Visits

    struct VisitPlan {
        /// Local visits to upload (new, changed, or merge winners).
        var toUpload: [Visit] = []
        /// Remote visits to insert on this phone.
        var toInsert: [VisitDTO] = []
        /// Local visits whose remote copy is newer: refresh the fields.
        var toUpdateLocal: [(local: Visit, remote: VisitDTO)] = []
        /// Local visits that lost a merge to a remote version: remove.
        var toDeleteLocal: [Visit] = []
        /// Remote rows that lost a merge to a local version: delete
        /// them from the backup, or they would merge again every sync.
        var toDeleteRemoteIDs: [UUID] = []
        /// How many same shop, same day pairs were folded together.
        var duplicatesMerged: Int = 0
    }

    static func visits(
        local: [Visit],
        remote: [VisitDTO],
        calendar: Calendar = .current
    ) -> VisitPlan {
        var plan = VisitPlan()
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        // Step 1: the same visit on both sides (same id). The newer
        // updated date wins; an equal date means already in sync. This
        // is not a duplicate merge, it is the same visit.
        var remainingLocal = local
        var remainingRemote: [VisitDTO] = []
        for dto in remote {
            if let match = localByID[dto.id] {
                if dto.updatedAt > match.updatedAt {
                    plan.toUpdateLocal.append((local: match, remote: dto))
                } else if match.updatedAt > dto.updatedAt {
                    plan.toUpload.append(match)
                }
                remainingLocal.removeAll { $0.id == dto.id }
            } else {
                remainingRemote.append(dto)
            }
        }

        // Step 2: the Stage 3 merge rule over what is left. A remote
        // visit for a shop and day the phone already has merges into
        // one visit; the version with more joggers wins.
        let remoteAsVisits = remainingRemote.map { $0.makeVisit() }
        let merged = VisitMerge.merge(local: remainingLocal, remote: remoteAsVisits, calendar: calendar)
        plan.duplicatesMerged = merged.duplicatesMerged

        let remainingLocalIDs = Set(remainingLocal.map(\.id))
        let remoteDTOByID = Dictionary(uniqueKeysWithValues: remainingRemote.map { ($0.id, $0) })
        let remoteKeys = Set(remainingRemote.map { VisitMerge.key(for: $0.makeVisit(), calendar: calendar) })

        for winner in merged.merged {
            if remainingLocalIDs.contains(winner.id) {
                // A local visit won. Upload it when it beat a remote
                // copy (the backup holds the losing version) or when
                // it has never been backed up.
                if remoteKeys.contains(VisitMerge.key(for: winner, calendar: calendar))
                    || winner.syncState != .synced {
                    plan.toUpload.append(winner)
                }
                // The remote loser for this key, if any, leaves the
                // backup so it never merges again.
                for dto in remainingRemote where dto.id != winner.id
                    && VisitMerge.key(for: dto.makeVisit(), calendar: calendar) == VisitMerge.key(for: winner, calendar: calendar) {
                    plan.toDeleteRemoteIDs.append(dto.id)
                }
            } else if let dto = remoteDTOByID[winner.id] {
                // A remote visit won. It lands on the phone, and the
                // local loser for its key leaves the phone.
                plan.toInsert.append(dto)
                for loser in remainingLocal where loser.id != winner.id
                    && VisitMerge.key(for: loser, calendar: calendar) == VisitMerge.key(for: winner, calendar: calendar) {
                    plan.toDeleteLocal.append(loser)
                }
            }
        }
        return plan
    }

    // MARK: - Want To Go

    struct WantToGoPlan {
        var toUpload: [WantToGoEntry] = []
        var toInsert: [WantToGoDTO] = []
        var toUpdateLocal: [(local: WantToGoEntry, remote: WantToGoDTO)] = []
        var toDeleteLocal: [WantToGoEntry] = []
        var toDeleteRemoteIDs: [UUID] = []
    }

    /// Want To Go merges by shop: the same shop saved on two phones is
    /// one entry, and the newer updated date wins. There is no duplicate
    /// count here; the counted confirmation line covers visits only.
    static func wantToGo(local: [WantToGoEntry], remote: [WantToGoDTO]) -> WantToGoPlan {
        var plan = WantToGoPlan()
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var remainingLocal = local
        var remainingRemote: [WantToGoDTO] = []

        for dto in remote {
            if let match = localByID[dto.id] {
                if dto.updatedAt > match.updatedAt {
                    plan.toUpdateLocal.append((local: match, remote: dto))
                } else if match.updatedAt > dto.updatedAt {
                    plan.toUpload.append(match)
                }
                remainingLocal.removeAll { $0.id == dto.id }
            } else {
                remainingRemote.append(dto)
            }
        }

        let remainingLocalByShop = Dictionary(uniqueKeysWithValues: remainingLocal.map { ($0.shopID, $0) })
        for dto in remainingRemote {
            if let match = remainingLocalByShop[dto.shopId] {
                if dto.updatedAt > match.updatedAt {
                    // Same shop, newer backup copy: refresh the local
                    // row in place, like the same-id path above.
                    plan.toUpdateLocal.append((local: match, remote: dto))
                } else {
                    plan.toUpload.append(match)
                    plan.toDeleteRemoteIDs.append(dto.id)
                }
            } else {
                plan.toInsert.append(dto)
            }
        }
        for entry in remainingLocal where !plan.toUpload.contains(where: { $0.id == entry.id })
            && !plan.toDeleteLocal.contains(where: { $0.id == entry.id })
            && entry.syncState != .synced {
            plan.toUpload.append(entry)
        }
        return plan
    }

    // MARK: - Companions

    struct CompanionPlan {
        var toUpload: [Companion] = []
        var toInsert: [CompanionDTO] = []
        /// Remote companion ids that match a local companion by name:
        /// visits arriving from the backup point at the local id instead,
        /// so one person never becomes two rows.
        var remapIDs: [UUID: UUID] = [:]
    }

    /// Companions merge by id, with a name fallback: the same name typed
    /// on two phones is one person, and the local row keeps its id.
    static func companions(local: [Companion], remote: [CompanionDTO]) -> CompanionPlan {
        var plan = CompanionPlan()
        let localIDs = Set(local.map(\.id))
        let localByName = Dictionary(
            uniqueKeysWithValues: local.map { ($0.name.lowercased(), $0) }
        )
        let remoteIDs = Set(remote.map(\.id))
        let remoteNames = Set(remote.map { $0.name.lowercased() })

        for dto in remote {
            if localIDs.contains(dto.id) {
                continue
            }
            if let match = localByName[dto.name.lowercased()] {
                plan.remapIDs[dto.id] = match.id
            } else {
                plan.toInsert.append(dto)
            }
        }
        for companion in local where !remoteIDs.contains(companion.id)
            && !remoteNames.contains(companion.name.lowercased()) {
            plan.toUpload.append(companion)
        }
        return plan
    }

    // MARK: - Settings

    enum SettingsPlan: Equatable {
        /// No remote row: upload the local settings.
        case uploadLocal
        /// The backup is newer: take its values.
        case applyRemote(UserSettingsDTO)
        /// This phone is newer: upload.
        case uploadLocalNewer
        /// Same version on both sides: nothing to do.
        case inSync
    }

    static func settings(local: UserSettings, remote: UserSettingsDTO?) -> SettingsPlan {
        guard let remote else { return .uploadLocal }
        if remote.updatedAt > local.updatedAt {
            return .applyRemote(remote)
        }
        if local.updatedAt > remote.updatedAt {
            return .uploadLocalNewer
        }
        return .inSync
    }
}
