# Packaging

`scripts/build-app.sh` assembles a standard macOS bundle using SwiftPM release output. `scripts/build-dmg.sh` signs nested code first, enables Hardened Runtime for Developer ID builds, creates the DMG, and optionally submits it with `notarytool`.

The scripts use `CFBundleShortVersionString` from `Resources/Info.plist` for local builds. A release workflow derives `VERSION` from its `v1.2.3` tag, sets the numeric `BUILD_NUMBER` from the workflow run number, and applies both values to the packaged app. The resulting disk image is named `ZvecStudio-1.2.3-arm64.dmg`.

## Direct distribution

Zvec Studio is distributed only as a downloadable DMG, not through the Mac App Store. Formal releases run on a fresh GitHub-hosted `macos-15` arm64 runner. The workflow imports the Developer ID certificate and App Store Connect API key from GitHub Actions secrets, then verifies the signature, notarization ticket, and Gatekeeper assessment before creating or updating the GitHub Release.

App Sandbox is intentionally disabled. Collection locations are chosen explicitly by the user and may exist anywhere they can access. The app does not use App Store provisioning profiles, receipts, or StoreKit distribution metadata. `LSApplicationCategoryType` remains useful LaunchServices metadata outside the App Store.

Local and pull-request builds use ad-hoc signing only for structural and launch verification; those DMGs are not release artifacts.

Configure these repository secrets before publishing a tag:

- `DEVELOPER_ID_CERTIFICATE_BASE64`: Base64-encoded Developer ID Application `.p12` file.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: Password used when exporting that `.p12` file.
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`: Base64-encoded App Store Connect API `.p8` key.
- `APP_STORE_CONNECT_KEY_ID`: API key ID.
- `APP_STORE_CONNECT_ISSUER_ID`: API issuer ID.

No self-hosted runner, preconfigured keychain, or local `notarytool` profile is required. GitHub-hosted `macos-15` supplies the arm64 macOS environment, Swift toolchain, and Apple command-line tools. The workflow removes imported credentials at the end of every run.

## zvec-swift dependency

The package pins public `zvec-swift` `v0.5.1`, while its manifest downloads `CZvec.xcframework.zip` from the `native-v0.5.1` GitHub Release. This release includes packaged-app resource lookup support, allowing `zvec-swift_Zvec.bundle` to live in the standard signed location at `Contents/Resources`.

## Scripts

- `build-app.sh` assembles and validates the `.app`, including its framework, resources, license, architecture, dependencies, and rpath.
- `build-dmg.sh` signs and verifies the app, notarizes when credentials are present, and creates the DMG.
- `make-app-icon.sh` is an optional maintenance tool. It reads the tracked 1024×1024 source at `Resources/AppIcon.png`, creates its iconset in the system temporary directory, and regenerates the tracked `Resources/AppIcon.icns`. Both icon files are versioned so a clean checkout can package the app without an asset-generation step.

The app bundle includes the project MIT license, `THIRD_PARTY_NOTICES.md`, and the resolved `zvec-swift` LICENSE and NOTICE files under `Contents/Resources`.
