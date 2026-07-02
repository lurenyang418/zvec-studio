# Zvec Studio

Native macOS management application for [Zvec](https://github.com/zvec-ai/zvec), built with SwiftUI and Swift Package Manager.

Zvec Studio provides a native interface for managing local collections. The interface includes:

- collection create, open, close, destroy, flush, optimize, statistics, and recent locations;
- schema add/alter/drop column and create/drop index operations with Apple-platform capability guards;
- document Insert, Update, Upsert, ID delete, filter delete, filter Browse, and ID Fetch;
- Vector, Full Text Match/Query, dense+sparse/full-text MultiQuery, and GroupBy query editors;
- type-aware Form and canonical Raw JSON editing for every public Zvec value family;
- RFC 4180 CSV and canonical JSON import preview, validation summaries, 500-document batches, and cancellation;
- current-result JSON/CSV export with metadata that explicitly does not claim to be a collection backup;
- persisted runtime configuration and controlled close-all/restart/shutdown behavior.

## Development

Requirements: Apple Silicon, macOS 15+, Swift 6.1, and internet access for the initial SwiftPM dependency download.

No Xcode project is used. Build and test from Terminal:

```sh
swift build
swift test
swift run ZvecStudio
```

Formatting and release packaging also run from Terminal:

```sh
xcrun swift-format lint --recursive --strict --configuration .swift-format Sources Tests Package.swift
scripts/build-app.sh
scripts/build-dmg.sh       # ad-hoc signed DMG
```

The package pins the public `zvec-swift` dependency to `v0.5.1`. Its binary XCFramework is downloaded from the matching `native-v0.5.1` GitHub Release. See [Packaging](Docs/Packaging.md).

Zvec Studio is distributed independently as an ad-hoc signed GitHub Release DMG. It is not Developer ID signed, notarized, or distributed through the App Store, and intentionally does not enable App Sandbox because users explicitly open and manage collections at arbitrary filesystem locations. macOS may require explicit approval before opening a downloaded build. See [Implementation Status](Docs/ImplementationStatus.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [SECURITY.md](SECURITY.md).

## License

Zvec Studio is available under the [MIT License](LICENSE). Bundled dependencies remain under their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
