import Foundation
import SwiftData
import CoreLocation
import UIKit

/// One arrival waiting for an answer: the in app check in prompt (Screen 6).
struct PendingArrival: Identifiable, Equatable {
    var id: UUID { shopID }
    var shopID: UUID
    var shopName: String
    var neighborhood: String
    var arrivedAt: Date
}

/// Orchestrates the automatic check in flow (Stories S5, S6, S7).
/// Region entry starts the brief stay check; the local notification prompt
/// is delivered only if the user is still inside the region when it
/// completes, and an exit cancels it. The visit always saves to SwiftData
/// before any jogger is offered (Flow C step 3).
@MainActor
final class CheckInManager: ObservableObject {
    /// The brief stay rule: a prompt fires only after this long inside a
    /// shop region, so walking past a shop never prompts.
    static let briefStaySeconds: TimeInterval = 300

    /// The in app prompt, shown as a sheet when set.
    @Published var pendingPrompt: PendingArrival?
    /// The visit just saved, shown in the confirmation sheet.
    @Published var savedVisit: Visit?
    /// The visit the Add Memory sheet is open for (Sprint 4). Set from
    /// the confirmation sheet after a save; cleared when the sheet closes.
    @Published var memoryVisit: Visit?
    /// Set when a check in hits same day duplicate protection, so the UI
    /// opens the existing visit instead of creating a second one.
    @Published var duplicateVisit: Visit?
    /// Today's dismissed arrivals, for the quiet recovery card.
    @Published var recoveryArrivals: [DismissedArrival] = []
    /// The shop a correction is being made from (Not This Shop flow).
    @Published var correctionSource: Shop?
    /// The visit a correction is editing (Sprint 4, Story S15). When set,
    /// picking a shop re-points this visit instead of saving a new one.
    /// Only the Add Memory sheet sets this; the prompt flow never does.
    var correctionTargetVisit: Visit?

    private let context: ModelContext
    private let visitStore: VisitStore
    private let locationService: LocationService
    private let notificationService: NotificationService

    init(
        context: ModelContext,
        locationService: LocationService,
        notificationService: NotificationService
    ) {
        self.context = context
        self.visitStore = VisitStore(context: context)
        self.locationService = locationService
        self.notificationService = notificationService

        // Callbacks hop to the main actor explicitly: location and
        // notification callbacks arrive outside Swift concurrency.
        locationService.onRegionEntry = { [weak self] shopID in
            Task { @MainActor in self?.handleRegionEntry(shopID) }
        }
        locationService.onRegionExit = { [weak self] shopID in
            Task { @MainActor in self?.handleRegionExit(shopID) }
        }
        locationService.onSignificantMove = { [weak self] in
            Task { @MainActor in self?.refreshMonitoredRegions() }
        }
        notificationService.onForegroundPrompt = { [weak self] shopID in
            Task { @MainActor in self?.deliverPrompt(for: shopID) }
        }
        notificationService.onNotificationTapped = { [weak self] shopID in
            Task { @MainActor in self?.deliverPrompt(for: shopID) }
        }
        notificationService.onCheckInAction = { [weak self] shopID in
            Task { @MainActor in self?.checkInFromNotification(shopID: shopID) }
        }
        notificationService.onNotThisShopAction = { [weak self] shopID in
            Task { @MainActor in self?.startCorrection(for: shopID) }
        }
        notificationService.onDismissAction = { [weak self] shopID in
            Task { @MainActor in self?.dismissFromNotification(shopID: shopID) }
        }

        refreshRecovery()
    }

    // MARK: - Region events

    private func handleRegionEntry(_ shopID: UUID) {
        guard promptsEnabled, let shop = fetchShop(id: shopID), !shop.isSample, shop.isPublished else { return }
        // Never prompt twice for the same day: an existing visit or a
        // dismissal already answers this arrival.
        if visitStore.existingVisit(shopID: shopID, on: Date()) != nil { return }
        if recoveryArrivals.contains(where: { $0.shopID == shopID }) { return }
        notificationService.scheduleArrivalPrompt(for: shop, after: Self.briefStaySeconds)
    }

    private func handleRegionExit(_ shopID: UUID) {
        // Leaving cancels the pending prompt: the no drive by rule.
        notificationService.cancelArrivalPrompt(for: shopID)
    }

    /// Delivers the prompt when the brief stay check completes. The
    /// foreground path double checks the user is still near the shop; the
    /// background notification path relies on the exit cancellation above.
    private func deliverPrompt(for shopID: UUID) {
        guard promptsEnabled, let shop = fetchShop(id: shopID), !shop.isSample, shop.isPublished else { return }
        if visitStore.existingVisit(shopID: shopID, on: Date()) != nil { return }
        if recoveryArrivals.contains(where: { $0.shopID == shopID }) { return }
        if let location = locationService.lastLocation,
           let distance = shop.distance(from: location),
           distance > LocationService.regionRadius * 3 {
            return
        }
        pendingPrompt = PendingArrival(
            shopID: shop.id,
            shopName: shop.name,
            neighborhood: shop.neighborhood,
            arrivedAt: Date()
        )
        let settings = UserSettings.current(in: context)
        settings.lastPromptDate = Date()
        settings.lastPromptShopName = shop.name
        settings.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Prompt answers

    /// One tap save from the prompt (Story S6). Returns the saved visit, or
    /// the existing visit when duplicate protection kicked in.
    func confirmCheckIn() {
        guard let prompt = pendingPrompt, let shop = fetchShop(id: prompt.shopID) else { return }
        pendingPrompt = nil
        save(shop: shop, source: .automatic)
    }

    func dismissPrompt() {
        guard let prompt = pendingPrompt, let shop = fetchShop(id: prompt.shopID) else {
            pendingPrompt = nil
            return
        }
        pendingPrompt = nil
        visitStore.recordDismissal(shop: shop)
        refreshRecovery()
    }

    func startCorrection(for shopID: UUID) {
        pendingPrompt = nil
        correctionTargetVisit = nil
        correctionSource = fetchShop(id: shopID)
    }

    /// Picks the corrected shop. In the prompt flow this saves the check
    /// in for the picked shop; when an edit is in progress it re-points
    /// the existing visit instead, and no new visit is created.
    func correctCheckIn(to shop: Shop) {
        correctionSource = nil
        if let target = correctionTargetVisit {
            correctionTargetVisit = nil
            do {
                try visitStore.repointVisit(target, to: shop)
            } catch {
                print("Visit correction failed: \(error.localizedDescription)")
            }
            return
        }
        save(shop: shop, source: .automatic)
    }

    func dismissCorrection() {
        correctionTargetVisit = nil
        correctionSource = nil
    }

    // MARK: - Visit editing (Sprint 4, Story S15)

    /// Starts a shop correction for an existing visit, from the Add Memory
    /// sheet. The correction list is the Sprint 3 path; the target is what
    /// makes it edit instead of check in.
    func beginVisitCorrection(for visit: Visit) {
        correctionTargetVisit = visit
    }

    /// Clears the edit target when the correction list is left without
    /// picking a shop.
    func endVisitCorrection() {
        correctionTargetVisit = nil
    }

    /// Applies the joggers from the Add Memory sheet to a saved visit.
    /// A failed save is logged, never silent, and the visit itself is
    /// never at risk: it was already saved at check in.
    func saveMemory(
        for visit: Visit,
        rating: Int?,
        tags: [String],
        orderText: String?,
        note: String?,
        companionNames: [String],
        photoFilename: String?
    ) {
        do {
            try visitStore.updateMemory(
                for: visit,
                rating: rating,
                tags: tags,
                orderText: orderText,
                note: note,
                companionNames: companionNames,
                photoFilename: photoFilename
            )
        } catch {
            print("Saving memory failed: \(error.localizedDescription)")
        }
    }

    /// Opens the Add Memory sheet for a saved visit, replacing the
    /// confirmation sheet in the single check in sheet.
    func openMemory(for visit: Visit) {
        savedVisit = nil
        memoryVisit = visit
    }

    func clearMemory() {
        memoryVisit = nil
    }

    // MARK: - Notification actions

    private func checkInFromNotification(shopID: UUID) {
        guard let shop = fetchShop(id: shopID) else { return }
        save(shop: shop, source: .automatic)
    }

    private func dismissFromNotification(shopID: UUID) {
        guard let shop = fetchShop(id: shopID) else { return }
        visitStore.recordDismissal(shop: shop)
        refreshRecovery()
    }

    // MARK: - Manual check in (Story S7)

    func manualCheckIn(shop: Shop) {
        save(shop: shop, source: .manual)
    }

    func checkInByTypedName(name: String, neighborhood: String, address: String, coordinate: CLLocationCoordinate2D?) {
        if let target = correctionTargetVisit {
            correctionTargetVisit = nil
            do {
                try visitStore.repointVisitToTypedName(
                    target,
                    name: name,
                    address: address,
                    neighborhood: neighborhood,
                    coordinate: coordinate
                )
            } catch {
                print("Visit correction failed: \(error.localizedDescription)")
            }
            return
        }
        do {
            let visit = try visitStore.saveUnverifiedVisit(
                name: name,
                address: address,
                neighborhood: neighborhood,
                coordinate: coordinate
            )
            savedVisit = visit
        } catch {
            print("Typed name check in failed: \(error.localizedDescription)")
        }
    }

    /// Logs a visit from the recovery card, then clears that dismissal.
    func checkInFromRecovery(_ arrival: DismissedArrival) {
        guard let shop = fetchShop(id: arrival.shopID) else { return }
        save(shop: shop, source: .manual)
    }

    // MARK: - Shared save path

    private func save(shop: Shop, source: VisitSource) {
        do {
            let result = try visitStore.saveCheckIn(shop: shop, source: source)
            if result.wasDuplicate {
                duplicateVisit = result.visit
            } else {
                savedVisit = result.visit
            }
            refreshRecovery()
        } catch {
            print("Check in failed: \(error.localizedDescription)")
        }
    }

    func clearConfirmation() {
        savedVisit = nil
    }

    /// Clears whichever check in sheet is showing after a swipe dismiss.
    /// A swiped away prompt counts as a dismissal: it saves nothing, never
    /// repeats for this arrival, and leaves the recovery card for today.
    /// A swiped away memory sheet just closes; the visit stays saved.
    func dismissActiveSheet() {
        if pendingPrompt != nil {
            dismissPrompt()
            return
        }
        if memoryVisit != nil {
            clearMemory()
            return
        }
        if savedVisit != nil {
            savedVisit = nil
            return
        }
        if correctionSource != nil {
            correctionSource = nil
        }
    }

    func clearDuplicate() {
        duplicateVisit = nil
    }

    // MARK: - Prompts setting and monitoring

    var promptsEnabled: Bool {
        UserSettings.current(in: context).autoCheckInPromptsEnabled
    }

    /// Turning prompts off takes effect immediately: monitoring stops and
    /// pending prompts are cancelled (Story S13).
    func setPromptsEnabled(_ enabled: Bool) {
        let settings = UserSettings.current(in: context)
        settings.autoCheckInPromptsEnabled = enabled
        settings.updatedAt = Date()
        try? context.save()
        if enabled {
            startMonitoring()
        } else {
            locationService.stopAllMonitoring()
            notificationService.cancelAllArrivalPrompts()
            pendingPrompt = nil
        }
    }

    /// Starts region monitoring for the nearest shops. Called on launch
    /// (when authorized and prompts are on) and when the user moves.
    func startMonitoring() {
        guard promptsEnabled, locationService.isAuthorized else { return }
        locationService.startSignificantChangeMonitoring()
        refreshMonitoredRegions()
    }

    func refreshMonitoredRegions() {
        guard promptsEnabled, locationService.isAuthorized else { return }
        let shops = (try? context.fetch(FetchDescriptor<Shop>())) ?? []
        let center = locationService.lastLocation
            ?? CLLocation(latitude: DetroitCenter.coordinate.latitude, longitude: DetroitCenter.coordinate.longitude)
        locationService.refreshMonitoredRegions(near: shops, center: center)
    }

    func refreshRecovery() {
        recoveryArrivals = visitStore.todaysDismissals()
    }

    // MARK: - Helpers

    func fetchShop(id: UUID) -> Shop? {
        var descriptor = FetchDescriptor<Shop>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
