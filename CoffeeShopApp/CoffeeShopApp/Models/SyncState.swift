import Foundation

/// Where a record stands against the backup (Sprint 6, Story S14).
/// Stored as `syncStateRaw` on Visit and WantToGoEntry, which Sprint 1
/// already carried for this sprint.
/// - local: never backed up, or signed out. Lives only on this phone.
/// - pending: changed on this phone since the last successful backup.
/// - synced: the backup holds this exact version.
enum SyncState: String {
    case local
    case pending
    case synced
}

extension Visit {
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }
}

extension WantToGoEntry {
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }
}
