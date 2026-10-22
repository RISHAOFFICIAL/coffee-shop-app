import SwiftUI

/// Root tab structure from the approved flow and hi-fi:
/// Discover, Visited, Want To Go, and Settings.
/// Per the HIG check recorded at lo-fi, the tab bar is navigation only.
/// Actions such as Check In live on their screens, never in the tab bar.
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Discover", systemImage: "map.fill") {
                DiscoverPlaceholderView()
            }
            Tab("Visited", systemImage: "bookmark.fill") {
                VisitedPlaceholderView()
            }
            Tab("Want To Go", systemImage: "heart.fill") {
                WantToGoPlaceholderView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsPlaceholderView()
            }
        }
        .tint(.caramel)
    }
}

#Preview {
    ContentView()
}
