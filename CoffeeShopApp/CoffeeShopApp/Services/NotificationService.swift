import Foundation
import UserNotifications

/// Local notifications for the arrival prompt (Sprint 3). The prompt is a
/// local notification with the approved actions: Check In, Not This Shop,
/// Dismiss. No remote push is used in version 1.
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    static let categoryID = "CHECK_IN_PROMPT"
    static let checkInActionID = "CHECK_IN"
    static let notThisShopActionID = "NOT_THIS_SHOP"
    static let dismissActionID = "DISMISS"
    static let shopIDUserInfoKey = "shopID"

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Plain language status for Settings. Notifications are local only:
    /// the prompt is scheduled on the phone, nothing is sent to a server.
    var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not set yet"
        case .denied:
            return "Off. Prompts cannot appear."
        case .authorized:
            return "On. Prompts can appear."
        case .provisional:
            return "On, quietly for now. Prompts can appear."
        case .ephemeral:
            return "On for this session."
        @unknown default:
            return "Unknown"
        }
    }

    /// Fired when the user taps Check In on the notification.
    var onCheckInAction: ((UUID) -> Void)?
    /// Fired when the user taps Not This Shop on the notification.
    var onNotThisShopAction: ((UUID) -> Void)?
    /// Fired when the user taps Dismiss on the notification.
    var onDismissAction: ((UUID) -> Void)?
    /// Fired when the user taps the notification body itself.
    var onNotificationTapped: ((UUID) -> Void)?
    /// Fired when a prompt notification fires while the app is open, so the
    /// app can show the in app prompt instead of a banner.
    var onForegroundPrompt: ((UUID) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
    }

    func configureCategories() {
        let checkIn = UNNotificationAction(
            identifier: Self.checkInActionID,
            title: "Check In",
            options: [.authenticationRequired]
        )
        let notThisShop = UNNotificationAction(
            identifier: Self.notThisShopActionID,
            title: "Not This Shop",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: Self.dismissActionID,
            title: "Dismiss",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [checkIn, notThisShop, dismiss],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            return granted
        } catch {
            return false
        }
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
        }
    }

    /// Schedules the arrival prompt to fire after the brief stay check.
    /// The delay is a notification trigger, not an app timer, so the prompt
    /// still arrives when the app is suspended or the phone is locked. An
    /// exit cancels it through `cancelArrivalPrompt`.
    func scheduleArrivalPrompt(for shop: Shop, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Were you at \(shop.name)?"
        content.body = "\(shop.neighborhood), Detroit. One tap saves this visit."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [Self.shopIDUserInfoKey: shop.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: requestIdentifier(for: shop.id),
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error {
                print("Failed to schedule arrival prompt: \(error.localizedDescription)")
            }
        }
    }

    func cancelArrivalPrompt(for shopID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier(for: shopID)])
    }

    func cancelAllArrivalPrompts() {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("arrival-") }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func requestIdentifier(for shopID: UUID) -> String {
        "arrival-\(shopID.uuidString)"
    }

    // MARK: - Delegate handling, called from AppDelegate

    /// A prompt fired while the app is open: show the in app prompt and
    /// suppress the banner.
    func handleForegroundNotification(_ notification: UNNotification) {
        guard let idString = notification.request.content.userInfo[Self.shopIDUserInfoKey] as? String,
              let shopID = UUID(uuidString: idString) else { return }
        onForegroundPrompt?(shopID)
    }

    func handleResponse(_ response: UNNotificationResponse) {
        guard let idString = response.notification.request.content.userInfo[Self.shopIDUserInfoKey] as? String,
              let shopID = UUID(uuidString: idString) else { return }
        switch response.actionIdentifier {
        case Self.checkInActionID:
            onCheckInAction?(shopID)
        case Self.notThisShopActionID:
            onNotThisShopAction?(shopID)
        case Self.dismissActionID:
            onDismissAction?(shopID)
        case UNNotificationDefaultActionIdentifier:
            onNotificationTapped?(shopID)
        default:
            break
        }
    }
}
