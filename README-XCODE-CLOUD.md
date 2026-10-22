# Coffee Shop App, Native iOS Scaffold and Xcode Cloud

Written for Risha, October 22, 2026. Sprint 0 of the approved Stage 6 build plan.

## What this is

A real Xcode project for the coffee shop app: SwiftUI, iPhone, iOS 26 minimum, following your standing route. Code lives in your GitHub, Xcode Cloud builds it, TestFlight delivers it to your iPhone, and your Mac is only needed for the one time workflow setup below.

What is real in this scaffold:

- The app opens to the approved four tabs: Discover, Visited, Want To Go, and Settings.
- Each tab states plainly what it will do and which sprint builds it. Nothing is presented as a working feature before its sprint. That honesty is deliberate, it is the lesson from the first hi-fi.
- The approved design tokens are in code (espresso, caramel, cream), and the app icon is a placeholder in those colors.
- A unit test target exists and runs, so the test pipeline is proven from the first build.

What is not done yet, by design: the data model and saving (Sprint 1), Discover (Sprint 2), check in (Sprint 3), and everything after. Each arrives in its sprint, with a report to you.

## The one time setup only you can do

Your Apple Developer enrollment is already active, so there is nothing to pay. These steps need your Apple ID and your Mac:

1. **Confirm App Store Connect.** Sign in at appstoreconnect.apple.com and confirm your membership shows active and any agreement Apple presents is accepted. I cannot accept agreements for you.
2. **Open the project on your Mac.** Open `CoffeeShopApp/CoffeeShopApp.xcodeproj` in Xcode. If Xcode asks about signing, sign in with your Apple ID and let it manage signing automatically. No development team is preset on purpose, so it uses yours.
3. **Create the first Xcode Cloud workflow.** In Xcode, use the Integrate menu, then Xcode Cloud, then Create Workflow, and pick the CoffeeShopApp scheme. This first workflow has to start from your Xcode, signed in as you. It is a one time step.
4. **Connect GitHub if Xcode asks.** Xcode Cloud builds from your repository (RISHAOFFICIAL/coffee-shop-app), so it may ask you to authorize the connection between App Store Connect and GitHub. Approve it with your accounts.
5. **Confirm the bundle ID when Xcode shows it.** The project currently proposes `com.lexissapphire.coffeeshopapp`. That is a proposal, not a decision. It can be changed freely before the first App Store submission, but the App Store Connect app record you create later must match it exactly, so we will confirm it together before that record exists.

After step 3, your part is done until a build lands in TestFlight for you to install.

## Supabase, one step that is also yours

The directory database schema is written and waiting at `07-native/supabase/schema.sql`. The Supabase project itself has to be created under your account (supabase.com, sign in, new project). When it exists, tell me and I will walk you through applying the schema, or apply it with you step by step. Nothing about the app is blocked today: Sprint 1 is where the directory gets wired in.

## What happens after setup

- Every push to the repository triggers an Xcode Cloud build. Your Mac does not need to be on.
- A passing build can go straight to TestFlight, so the app lands on your iPhone the same way you reviewed the prototypes.
- Build results show in App Store Connect and Xcode. A failed build tells us exactly what to fix, and a small fix pass after the very first build is expected and planned.

## The honest limits

- **This scaffold is not compile verified yet.** There is no Xcode or Swift compiler in my environment. The project file has been structurally checked (every referenced file exists, the scheme is valid), but the first real compile is the first Xcode Cloud build. Do not let anyone call it verified before that.
- **The app has no final name yet.** "Coffee Shop App" in the project is a working title only. The App Store name is your decision, and it is needed before the App Store Connect record is created, not before the first build.
- **TestFlight builds expire 90 days after upload.** A fresh build keeps testing alive; nothing about that is a problem, it is just how TestFlight works.
- TestFlight internal testers must be App Store Connect users on your team (up to 100). Friends and colleagues who are not on your team test through external TestFlight later, with your approval for each release.
