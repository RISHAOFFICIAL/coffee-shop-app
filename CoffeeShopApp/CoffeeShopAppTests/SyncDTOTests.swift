import Foundation
import Testing
@testable import CoffeeShopApp

/// The sync wire format (Sprint 6, Story S14): DTOs encode with
/// snake_case keys and fractional second ISO 8601 dates, exactly as
/// Supabase returns them, and decode back to the same values. A
/// round trip that loses a jogger would lose a memory.
struct SyncDTOTests {
    private static let ownerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let stamp = Date(timeIntervalSince1970: 1_792_000_000.5)

    private static func makeVisit() -> Visit {
        let visit = Visit(
            shopID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            shopName: "Test Coffee",
            neighborhood: "Midtown",
            address: "1 Test Street",
            checkedInAt: stamp,
            source: .manual,
            rating: 5,
            tags: ["Cozy", "Quiet"],
            orderText: "Latte",
            note: "Good morning spot",
            companionIDs: [UUID(uuidString: "33333333-3333-3333-3333-333333333333")!],
            photoFilename: "some-id.jpg",
            isUnverifiedShop: false,
            createdAt: stamp,
            updatedAt: stamp
        )
        return visit
    }

    @Test func visitDTORoundTripsWithSnakeCaseKeys() throws {
        let visit = Self.makeVisit()
        let dto = VisitDTO(from: visit, ownerID: Self.ownerID, photoPath: "11111111-1111-1111-1111-111111111111/visit.jpg")
        let data = try SupabaseJSON.encoder().encode(dto)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("shop_id"))
        #expect(text.contains("checked_in_at"))
        #expect(text.contains("order_text"))
        #expect(text.contains("companion_ids"))
        #expect(text.contains("photo_path"))
        #expect(text.contains("is_unverified_shop"))
        let decoded = try SupabaseJSON.decoder().decode(VisitDTO.self, from: data)
        #expect(decoded == dto)
        #expect(decoded.joggerCount == 6)
    }

    @Test func visitDTOParsesFractionalSecondDates() throws {
        let json = """
        {"id":"\(UUID().uuidString)","owner_id":"\(Self.ownerID.uuidString)","shop_id":"\(UUID().uuidString)","shop_name":"Test Coffee","neighborhood":"Midtown","address":"1 Test Street","checked_in_at":"2026-11-23T15:04:05.123456+00:00","source":"manual","rating":5,"tags":["Cozy"],"order_text":null,"note":null,"companion_ids":[],"photo_path":null,"is_unverified_shop":false,"created_at":"2026-11-23T15:04:05.123456+00:00","updated_at":"2026-11-23T15:04:05.123456+00:00"}
        """
        let dto = try SupabaseJSON.decoder().decode(VisitDTO.self, from: Data(json.utf8))
        #expect(dto.shopName == "Test Coffee")
        #expect(dto.rating == 5)
        #expect(dto.tags == ["Cozy"])
        #expect(dto.orderText == nil)
    }

    @Test func visitDTOMakeVisitMapsEveryField() {
        let visit = Self.makeVisit()
        let dto = VisitDTO(from: visit, ownerID: Self.ownerID, photoPath: "owner/visit.jpg")
        let restored = dto.makeVisit()
        #expect(restored.id == visit.id)
        #expect(restored.shopID == visit.shopID)
        #expect(restored.shopName == visit.shopName)
        #expect(restored.checkedInAt == visit.checkedInAt)
        #expect(restored.rating == 5)
        #expect(restored.tags == ["Cozy", "Quiet"])
        #expect(restored.orderText == "Latte")
        #expect(restored.note == "Good morning spot")
        #expect(restored.companionIDs == visit.companionIDs)
        #expect(restored.photoFilename == VisitPhotoStore.filename(for: visit.id))
        #expect(restored.syncState == .synced)
    }

    @Test func visitDTOMakeVisitWithoutPhotoHasNoFilename() {
        let dto = VisitDTO(from: Self.makeVisit(), ownerID: Self.ownerID, photoPath: nil)
        #expect(dto.makeVisit().photoFilename == nil)
    }

    @Test func wantToGoDTORoundTrips() throws {
        let entry = WantToGoEntry(
            shopID: UUID(),
            shopName: "Test Coffee",
            neighborhood: "Midtown",
            address: "1 Test Street",
            sharedBy: "Aric",
            noteFromSharer: "Try the cold brew",
            addedAt: Self.stamp,
            updatedAt: Self.stamp
        )
        let dto = WantToGoDTO(from: entry, ownerID: Self.ownerID)
        let data = try SupabaseJSON.encoder().encode(dto)
        let decoded = try SupabaseJSON.decoder().decode(WantToGoDTO.self, from: data)
        #expect(decoded == dto)
        let restored = dto.makeEntry()
        #expect(restored.shopName == "Test Coffee")
        #expect(restored.sharedBy == "Aric")
        #expect(restored.noteFromSharer == "Try the cold brew")
        #expect(restored.syncState == .synced)
    }

    @Test func companionDTORoundTrips() throws {
        let companion = Companion(name: "Aric", createdAt: Self.stamp, updatedAt: Self.stamp)
        let dto = CompanionDTO(from: companion, ownerID: Self.ownerID)
        let data = try SupabaseJSON.encoder().encode(dto)
        let decoded = try SupabaseJSON.decoder().decode(CompanionDTO.self, from: data)
        #expect(decoded == dto)
        #expect(dto.makeCompanion().name == "Aric")
    }

    @Test func userSettingsDTORoundTrips() throws {
        let settings = UserSettings(
            autoCheckInPromptsEnabled: false,
            shareNotesByDefault: true,
            sharerName: "Risha",
            updatedAt: Self.stamp
        )
        let dto = UserSettingsDTO(from: settings, userID: Self.ownerID)
        let data = try SupabaseJSON.encoder().encode(dto)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("auto_check_in_prompts_enabled"))
        #expect(text.contains("share_notes_by_default"))
        #expect(text.contains("sharer_name"))
        let decoded = try SupabaseJSON.decoder().decode(UserSettingsDTO.self, from: data)
        #expect(decoded == dto)
        #expect(decoded.autoCheckInPromptsEnabled == false)
        #expect(decoded.shareNotesByDefault == true)
        #expect(decoded.sharerName == "Risha")
    }
}
