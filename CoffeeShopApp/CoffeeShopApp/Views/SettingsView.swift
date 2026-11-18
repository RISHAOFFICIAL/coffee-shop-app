import SwiftUI
import SwiftData

/// Settings (Screen 16), Sprint 3 minimal version: the auto check in
/// prompts toggle with its honest status line, location access status with
/// a hand off to iOS Settings, and the sharing default. Sign in, backup,
/// sign out, and account deletion arrive in Sprint 6; this screen says so
/// instead of showing controls that cannot work yet.
struct SettingsView: View {
    @Query private var settingsRows: [UserSettings]
    @EnvironmentObject private var checkInManager: CheckInManager
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var directoryStore: DirectoryStore
    @Environment(\.modelContext) private var modelContext

    private var settings: UserSettings? { settingsRows.first }

    var body: some View {
        NavigationStack {
            Form {
                promptsSection
                locationSection
                sharingSection
                backupSection
                directorySection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Prompts

    private var promptsSection: some View {
        Section {
            Toggle("Auto Check In Prompts", isOn: promptsBinding)
            if let settings {
                Text(settings.promptsStatusText)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            if promptsBlockedByPermission {
                Text("Location is off, so prompts cannot appear. Open the phone setting to change it.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.closedRed)
            }
        } header: {
            Text("Privacy and Location")
        }
    }

    private var promptsBlockedByPermission: Bool {
        guard let settings, settings.autoCheckInPromptsEnabled else { return false }
        return locationService.authorizationStatus == .denied
            || locationService.authorizationStatus == .restricted
    }

    private var promptsBinding: Binding<Bool> {
        Binding(
            get: { settings?.autoCheckInPromptsEnabled ?? true },
            set: { newValue in checkInManager.setPromptsEnabled(newValue) }
        )
    }

    // MARK: - Location

    private var locationSection: some View {
        Section("Location Access") {
            Button(action: openSystemSettings) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(locationService.authorizationDescription)
                            .font(.coffeeBody)
                            .foregroundStyle(.appText)
                        Text("Open the phone setting to change it")
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appTextSecondary)
                }
            }
            .buttonStyle(.plain)
            if locationService.isAuthorized {
                Text("\(locationService.monitoredShopCount) nearby shops watched for arrival prompts.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
        }
    }

    // MARK: - Sharing and backup

    private var sharingSection: some View {
        Section("Sharing") {
            Toggle("Share Notes By Default", isOn: shareNotesBinding)
            Text(shareNotesStatusText)
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
        }
    }

    private var shareNotesStatusText: String {
        if settings?.shareNotesByDefault == true {
            return "On, your note is included unless you remove it."
        }
        return "Off, you choose per share."
    }

    private var shareNotesBinding: Binding<Bool> {
        Binding(
            get: { settings?.shareNotesByDefault ?? false },
            set: { newValue in
                guard let settings else { return }
                settings.shareNotesByDefault = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var backupSection: some View {
        Section("Backup") {
            Text("Local Only. Your log lives on this phone.")
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            Text("Sign in for backup arrives in Sprint 6. Until then, your visits are safe on this phone but are not backed up anywhere else.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
        }
    }

    // MARK: - Directory and about

    private var directorySection: some View {
        Section("Directory") {
            Text(directoryStatusText)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
        }
    }

    private var directoryStatusText: String {
        switch directoryStore.state {
        case .loading:
            return "Loading Detroit shops..."
        case .loaded(let count, let lastUpdated):
            return "\(count) Detroit shops. Updated \(mediumDate(lastUpdated))."
        case .offlineCached(let count, let lastUpdated):
            return "\(count) Detroit shops, saved. Updated \(mediumDate(lastUpdated))."
        case .empty:
            return "No shops in the directory yet."
        case .error:
            return "The directory could not load."
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("Coffee Shop App, version 1.0")
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            Text("Working title. The final app name is still to be decided.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
            #if DEBUG
            Text("Debug build. Sample shops appear only here and never in a TestFlight build.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
            #endif
        }
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
