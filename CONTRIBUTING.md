# Contributing

Contributions are welcome through issues and pull requests.

## Development setup

Requirements:

- Apple Silicon Mac running macOS 15 or later
- Swift 6.1 or later
- Command Line Tools or Xcode toolchain providing SwiftPM and `swift-format`

This is a Swift Package Manager project. No Xcode project is used or required.

```sh
swift build
swift test
swift run ZvecStudio
```

## Before submitting

1. Keep changes focused and preserve Swift 6 strict-concurrency safety.
2. Add or update tests for behavior changes.
3. Run formatting, tests, and diff validation:

   ```sh
   xcrun swift-format format --in-place --recursive --configuration .swift-format Sources Tests Package.swift
   xcrun swift-format lint --recursive --strict --configuration .swift-format Sources Tests Package.swift
   swift test
   git diff --check
   ```

4. For packaging changes, also run `scripts/build-dmg.sh` and inspect the generated app bundle.
5. Update `CHANGELOG.md` for user-visible changes.

Do not commit build directories, DMGs, signing credentials, local environment files, or generated temporary iconsets. Read and follow the [Code of Conduct](CODE_OF_CONDUCT.md).
