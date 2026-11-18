import SwiftUI

/// Want To Go (Screen 13). The full list arrives in Sprint 5 with shared
/// shop saving, Directions, and Check In There. Until then this tab says
/// so honestly instead of showing a list that cannot work yet.
struct WantToGoView: View {
    var body: some View {
        ScaffoldNoticeView(
            title: "Want To Go",
            message: "Shops friends share with you and shops you save for later, each with directions and a check in that moves it into Visited once you have been.",
            sprint: "Want To Go is built in Sprint 5."
        )
    }
}
