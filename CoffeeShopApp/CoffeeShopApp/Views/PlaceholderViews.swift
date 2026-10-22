import SwiftUI

/// Sprint 0 placeholder tabs. Each one says what the finished tab does and
/// which sprint builds it, per the approved build plan. These are replaced
/// sprint by sprint; nothing here is a finished feature.

struct DiscoverPlaceholderView: View {
    var body: some View {
        ScaffoldNoticeView(
            title: "Discover",
            message: "Every Detroit coffee shop on a map and in a list, searchable by name and neighborhood, with Open Now and Independent Only filters.",
            sprint: "Sprint 0 scaffold. Discover is built in Sprint 2."
        )
    }
}

struct VisitedPlaceholderView: View {
    var body: some View {
        ScaffoldNoticeView(
            title: "Visited",
            message: "Your personal log of shops you have checked in to, searchable by neighborhood, who you were with, what you ordered, and your tags, so a forgotten shop takes seconds to find.",
            sprint: "Sprint 0 scaffold. Check in is Sprint 3, Visited is Sprint 5."
        )
    }
}

struct WantToGoPlaceholderView: View {
    var body: some View {
        ScaffoldNoticeView(
            title: "Want To Go",
            message: "Shops friends share with you and shops you save for later, each with directions and a check in that moves it into Visited once you have been.",
            sprint: "Sprint 0 scaffold. Want To Go is built in Sprint 5."
        )
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        ScaffoldNoticeView(
            title: "Settings",
            message: "Auto check in prompts, sharing defaults, location access status, backup status, and sign in. Your log lives on this phone first, always.",
            sprint: "Sprint 0 scaffold. Settings is built in Sprint 6."
        )
    }
}
