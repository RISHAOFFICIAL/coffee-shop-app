import SwiftUI
import SwiftData

/// Root tab structure from the approved flow and hi-fi:
/// Discover, Visited, Want To Go, and Settings.
/// Per the HIG check recorded at lo-fi, the tab bar is navigation only.
/// Actions such as Check In live on their screens, never in the tab bar.
/// The tab bar uses the native iOS 26 Liquid Glass treatment.
/// This view also owns the first launch gate and the check in sheets, so a
/// prompt, confirmation, or correction can appear over any tab.
struct ContentView: View {
    @EnvironmentObject private var checkInManager: CheckInManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    private enum AppTab: Hashable {
        case discover
        case visited
        case wantToGo
        case settings
    }

    /// The single check in sheet, so a prompt can turn into a confirmation
    /// or a correction without a sheet swap glitch.
    private enum CheckInSheet: Identifiable {
        case prompt(PendingArrival)
        case confirmation(Visit)
        case memory(Visit)
        case correction(Shop)

        var id: String {
            switch self {
            case .prompt(let prompt): return "prompt-\(prompt.shopID.uuidString)"
            case .confirmation(let visit): return "confirmation-\(visit.id.uuidString)"
            case .memory(let visit): return "memory-\(visit.id.uuidString)"
            case .correction(let shop): return "correction-\(shop.id.uuidString)"
            }
        }
    }

    @State private var selectedTab: AppTab = .discover

    private var hasCompletedFirstLaunch: Bool {
        settingsRows.first?.hasCompletedFirstLaunch ?? false
    }

    private var activeSheet: CheckInSheet? {
        if let shop = checkInManager.correctionSource {
            return .correction(shop)
        }
        if let visit = checkInManager.memoryVisit {
            return .memory(visit)
        }
        if let visit = checkInManager.savedVisit {
            return .confirmation(visit)
        }
        if let prompt = checkInManager.pendingPrompt {
            return .prompt(prompt)
        }
        return nil
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Discover", systemImage: "map.fill", value: .discover) {
                DiscoverView()
            }
            Tab("Visited", systemImage: "bookmark.fill", value: .visited) {
                VisitedView()
            }
            Tab("Want To Go", systemImage: "heart.fill", value: .wantToGo) {
                WantToGoView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .tint(.appAccent)
        .task {
            _ = UserSettings.current(in: modelContext)
        }
        .onChange(of: locationService.authorizationStatus) { _, _ in
            // Authorization granted after first launch: start watching.
            checkInManager.startMonitoring()
        }
        .fullScreenCover(isPresented: .constant(!hasCompletedFirstLaunch)) {
            FirstLaunchView(onComplete: completeFirstLaunch)
        }
        .sheet(
            item: Binding<CheckInSheet?>(
                get: { activeSheet },
                set: { newValue in
                    if newValue == nil {
                        checkInManager.dismissActiveSheet()
                    }
                }
            )
        ) { sheet in
            switch sheet {
            case .prompt(let prompt):
                CheckInPromptView(prompt: prompt)
            case .confirmation(let visit):
                CheckInConfirmationView(
                    visit: visit,
                    onAddMemory: {
                        checkInManager.openMemory(for: visit)
                    },
                    onViewInVisited: {
                        checkInManager.clearConfirmation()
                        selectedTab = .visited
                    },
                    onDone: {
                        checkInManager.clearConfirmation()
                    }
                )
            case .memory(let visit):
                AddMemoryView(visit: visit)
            case .correction(let shop):
                CorrectionView(sourceShop: shop)
            }
        }
        .alert(
            "Already logged today",
            isPresented: Binding(
                get: { checkInManager.duplicateVisit != nil },
                set: { showing in
                    if !showing { checkInManager.clearDuplicate() }
                }
            )
        ) {
            Button("View in Visited") {
                checkInManager.clearDuplicate()
                selectedTab = .visited
            }
            Button("OK", role: .cancel) {
                checkInManager.clearDuplicate()
            }
        } message: {
            Text("This shop is already in your Visited list for today.")
        }
    }

    private func completeFirstLaunch() {
        let settings = UserSettings.current(in: modelContext)
        settings.hasCompletedFirstLaunch = true
        settings.updatedAt = Date()
        try? modelContext.save()
    }
}

#Preview {
    ContentView()
}
