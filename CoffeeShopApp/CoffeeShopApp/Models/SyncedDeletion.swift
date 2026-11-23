import Foundation
import SwiftData

/// A record of a deletion that still has to reach the backup (Sprint 6,
/// Story S13 and S14). When a visit or Want To Go entry that was already
/// backed up is deleted on the phone, its tombstone is what removes the
/// remote copy on the next sync, so a deleted visit can never come back
/// from the backup. A record that was never backed up needs no tombstone:
/// there is nothing remote to delete.
/// Undo removes the tombstone again, so the backup keeps the visit.
@Model
final class SyncedDeletion {
    @Attribute(.unique) var id: UUID
    /// The id of the deleted Visit or WantToGoEntry.
    var recordID: UUID
    var kindRaw: String
    var deletedAt: Date

    enum Kind: String {
        case visit
        case wantToGo
    }

    init(
        id: UUID = UUID(),
        recordID: UUID,
        kind: Kind,
        deletedAt: Date = Date()
    ) {
        self.id = id
        self.recordID = recordID
        self.kindRaw = kind.rawValue
        self.deletedAt = deletedAt
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .visit }
        set { kindRaw = newValue.rawValue }
    }

    /// Records a deletion, once. A second record for the same id is a
    /// no-op, so repeated deletes of the same record cannot pile up.
    static func record(recordID: UUID, kind: Kind, in context: ModelContext) {
        let existing = all(in: context).first { $0.recordID == recordID && $0.kind == kind }
        guard existing == nil else { return }
        context.insert(SyncedDeletion(recordID: recordID, kind: kind))
        try? context.save()
    }

    /// Drops the tombstone, used by Undo: the backup keeps the visit.
    static func remove(recordID: UUID, kind: Kind, in context: ModelContext) {
        for tombstone in all(in: context) where tombstone.recordID == recordID && tombstone.kind == kind {
            context.delete(tombstone)
        }
        try? context.save()
    }

    static func all(in context: ModelContext) -> [SyncedDeletion] {
        (try? context.fetch(FetchDescriptor<SyncedDeletion>())) ?? []
    }

    static func removeAll(_ tombstones: [SyncedDeletion], in context: ModelContext) {
        for tombstone in tombstones {
            context.delete(tombstone)
        }
        try? context.save()
    }
}
