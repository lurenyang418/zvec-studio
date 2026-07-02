# Packaging

`scripts/build-app.sh` assembles a standard macOS bundle using SwiftPM release output. `scripts/build-dmg.sh` ad-hoc signs the nested code and app bundle, verifies their structure, and creates the DMG.

The scripts use `CFBundleShortVersionString` from `Resources/Info.plist` for local builds. A release workflow derives `VERSION` from its `v1.2.3` tag, sets the numeric `BUILD_NUMBER` from the workflow run number, and applies both values to the packaged app. The resulting disk image is named `ZvecStudio-1.2.3-arm64.dmg`.

## Direct distribution

Zvec Studio is distributed only as a downloadable DMG, not through the Mac App Store. Releases run on a fresh GitHub-hosted `macos-15` arm64 runner, use ad-hoc code signing, and are published directly to GitHub Releases. This matches the current project requirement and needs no Apple credentials or repository secrets.

App Sandbox is intentionally disabled. Collection locations are chosen explicitly by the user and may exist anywhere they can access. The app does not use App Store provisioning profiles, receipts, or StoreKit distribution metadata. `LSApplicationCategoryType` remains useful LaunchServices metadata outside the App Store.

Ad-hoc signing verifies bundle integrity but does not establish a trusted Developer ID and cannot be notarized. Users may therefore see a Gatekeeper warning when opening a downloaded build and may need to explicitly approve the app in Finder or System Settings. If the project later obtains an Apple Developer Program membership, Developer ID signing and notarization can be added without changing the SwiftPM build.

No self-hosted runner, preconfigured keychain, Apple credential, or additional release secret is required. GitHub-hosted `macos-15` supplies the arm64 macOS environment, Swift toolchain, and Apple command-line tools.

## zvec-swift dependency

The package pins public `zvec-swift` `v0.5.1`, while its manifest downloads `CZvec.xcframework.zip` from the `native-v0.5.1` GitHub Release. This release includes packaged-app resource lookup support, allowing `zvec-swift_Zvec.bundle` to live in the standard signed location at `Contents/Resources`.

## Scripts

- `build-app.sh` assembles and validates the `.app`, including its framework, resources, license, architecture, dependencies, and rpath.
- `build-dmg.sh` ad-hoc signs and verifies the app, then creates the DMG.
- `make-app-icon.sh` is an optional maintenance tool. It reads the tracked 1024×1024 source at `Resources/AppIcon.png`, creates its iconset in the system temporary directory, and regenerates the tracked `Resources/AppIcon.icns`. Both icon files are versioned so a clean checkout can package the app without an asset-generation step.

The app bundle includes the project MIT license, `THIRD_PARTY_NOTICES.md`, and the resolved `zvec-swift` LICENSE and NOTICE files under `Contents/Resources`.
