# Coffee Shop App, Terminal Check

For Risha, Oct 23, 2026. This replaces the click through Xcode route as the first local check, at Risha's direction. The goal is narrow: prove the scaffold compiles on her Mac and get the exact output if it does not. Signing, running in the simulator by hand, and the Xcode Cloud workflow come after this check, in that order, one at a time.

Rules for this route:
- One command at a time. Paste the command, press Return, send Muse what Terminal prints.
- Do not type any password or token into this chat. If Terminal ever asks for a GitHub token, stop and say so.
- Nothing here deletes or overwrites her saved copy.

## Step 1: Find the saved project

Open Terminal on the Mac (Spotlight, type Terminal, press Return) and paste:

```bash
mdfind -name CoffeeShopApp.xcodeproj
```

Send Muse the line it prints. That line is the path to the project she saved. If it prints nothing, say "nothing printed" and Muse will give the clone command next instead.

## Step 2: Go to the project and update it

Muse will turn the Step 1 path into the exact cd command for her machine, because the save location is hers. From the repository root, the update is:

```bash
git pull
```

Expected: "Already up to date" or a short list of updated files. If git asks for credentials, stop and tell Muse.

## Step 3: Confirm the tools and the scheme

```bash
xcodebuild -version
xcodebuild -list -project CoffeeShopApp/CoffeeShopApp.xcodeproj
```

Expected: an Xcode version line, and a list that includes the scheme CoffeeShopApp and the target CoffeeShopAppTests. Send Muse the output if either command errors.

## Step 4: Compile check, no signing needed

This builds the app and the test target for a generic simulator with code signing switched off, so no development team is required for this step. It answers one question only: does the code compile on a real Mac?

```bash
xcodebuild build-for-testing -project CoffeeShopApp/CoffeeShopApp.xcodeproj -scheme CoffeeShopApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Expected success ending: ** TEST BUILD SUCCEEDED ** (the wording "build succeeded" is the part that matters). If it fails, Terminal prints errors in red text starting with "error:". Copy from the first "error:" line to the end and send it to Muse. That output is the planned first build fix pass input.

## What Terminal cannot do in Sprint 0

- It cannot create the first Xcode Cloud workflow. Apple starts that from Xcode under her account. That stays a later, separate step, done live together after the compile check passes.
- It cannot accept App Store Connect agreements or create her Supabase project. Both remain short account holder steps, also later and separate.
- A compile pass here is not a device pass. Running the app, first on a simulator and then on her iPhone, comes after this check.
