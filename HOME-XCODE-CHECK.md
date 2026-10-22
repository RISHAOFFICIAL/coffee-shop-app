# Check the Coffee Shop App in Xcode at Home

For Risha. This is the short, exact path from GitHub to seeing the scaffold run. Work through it in order and stop at the first screen that does not match. Send Muse a screenshot of that screen or the first red error, and do not try random fixes.

## 1. Get the project onto your Mac

Use Xcode's clone flow:

1. Open Xcode.
2. On the welcome window, choose **Clone Git Repository**. If there is no welcome window, use **File, Clone Repository**.
3. Paste this repository address exactly:

   `https://github.com/RISHAOFFICIAL/coffee-shop-app.git`

4. Sign in to GitHub if Xcode asks.
5. Choose where to save it. The default location is fine. If your Mac says a folder named `coffee-shop-app` already exists there, choose a different parent folder rather than overwriting anything.
6. Wait for the clone to finish.

You should now have this project file:

`coffee-shop-app/CoffeeShopApp/CoffeeShopApp.xcodeproj`

## 2. Open the right project

1. In Xcode, open `CoffeeShopApp.xcodeproj` if it did not open automatically.
2. Wait until indexing finishes and the spinning indicator near the top stops.
3. Confirm the left sidebar shows folders named CoffeeShopApp, Components, Views, and CoffeeShopAppTests.
4. Near the top, confirm the selected scheme says **CoffeeShopApp**.

If Xcode asks whether to trust or open the project, open it. It is the project from your own private GitHub repository.

## 3. Let Xcode use your signing team

The scaffold intentionally has no development team saved in it.

1. In the left sidebar, click the blue **CoffeeShopApp** project icon at the top.
2. Under Targets, select **CoffeeShopApp**.
3. Open **Signing & Capabilities**.
4. If no account is signed in, Xcode may direct you to **Xcode, Settings, Accounts**. Add your Apple ID there, then return to Signing & Capabilities.
5. Make sure **Automatically manage signing** is checked.
6. For Team, select your Apple Developer account or personal team.
7. Leave the bundle identifier as `com.lexissapphire.coffeeshopapp` for this check. It is still a proposal and does not need to be finalized tonight.

If Xcode changes signing settings locally, that is expected. You do not need to save, commit, or upload anything yourself.

## 4. Run it in the simulator first

The simulator is the cleanest first check because it separates "does the code build" from any phone signing or trust issue.

1. Next to the scheme near the top of Xcode, choose an iPhone simulator that runs iOS 26. The exact iPhone model does not matter.
2. Press **Command-R**, or use **Product, Run**.
3. Wait for the build. The first build can take a few minutes.

### What success looks like

The simulator should open to a warm cream screen with:

- A coffee cup icon in caramel
- The heading **Discover**
- Text explaining the Detroit coffee shop directory
- A pill that says **Sprint 0 scaffold. Discover is built in Sprint 2.**
- Four tabs at the bottom: Discover, Visited, Want To Go, and Settings

Tap each tab. Each one should open and honestly state which sprint builds it. Nothing else is supposed to function yet.

## 5. Run the smoke test

1. Press **Command-U**, or use **Product, Test**.
2. Success is **Test Succeeded**, or a green check beside `scaffoldBuilds` in the test results.

This only proves that the app compiled and the test pipeline works. It does not prove the finished app's features, which have not been built yet.

## 6. If it stops or shows a red error

Stop there and send Muse one of these:

- A screenshot of the whole Xcode window, or
- The exact text of the first red error

Especially useful screenshots are:

- The Signing & Capabilities page if the error mentions a development team, signing, or provisioning
- The top destination selector if no iOS 26 simulator is available
- The first compiler error in the Issues view

Do not change the bundle ID, delete files, or follow a random suggested fix. The first build log is exactly what Muse needs for the planned fix pass.

## 7. Optional tonight: create the Xcode Cloud workflow

Only do this if the local run worked and you feel like continuing:

1. Use **Integrate, Xcode Cloud, Create Workflow**.
2. Choose the **CoffeeShopApp** scheme.
3. Authorize the connection to GitHub if Apple asks.
4. Tell Muse when the first cloud build starts and send its result or a screenshot.

That workflow is the one remaining setup step that turns future pushes into automatic builds and TestFlight deliveries.

## 8. Tell Muse the result

Any one of these replies is enough:

- "It ran in the simulator"
- "The test passed too"
- "It stopped here" plus the screenshot
- Your iPhone model and the iOS version from Settings, General, About

That closes the local check portion of Sprint 0. The sprint itself closes after the first Xcode Cloud build result is recorded.
