import Testing
@testable import CoffeeShopApp

/// Sprint 0 smoke tests. Their job is to prove the test target runs in
/// Xcode Cloud from the very first build, so later sprints inherit a
/// working test pipeline instead of discovering a broken one in Sprint 3.
/// Real logic tests arrive with the logic, sprint by sprint.
struct CoffeeShopAppTests {

    @Test func scaffoldBuilds() {
        // Reaching this assertion means the app module compiled and linked
        // into the test bundle, which is the Sprint 0 bar.
        #expect(Bool(true))
    }
}
