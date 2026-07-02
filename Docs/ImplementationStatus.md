# Implementation Status

The implementation in this repository provides:

- SwiftPM-only Swift 6.1/macOS 15 application and core targets;
- runtime and multi-collection lifecycle management;
- document CRUD, filter browse, fetch, schema DDL, index management, and every
  public query family exposed by `zvec-swift`;
- canonical JSON and RFC 4180 CSV import/export, validation preview, detailed
  write results, 500-document batching, and cancellation boundaries;
- SwiftUI management views, destructive-operation confirmation, runtime
  settings, and delayed application shutdown;
- unit/integration tests plus app, DMG, signature, rpath, and resource
  validation.

## Release prerequisite

The source and native binary are published as `zvec-swift` `v0.5.1` and
`native-v0.5.1`, and this package uses that fixed public dependency. A formal
direct distribution runs entirely on a fresh GitHub-hosted macOS runner. It
imports the Developer ID certificate and App Store Connect notarization key
from repository secrets; no self-hosted runner or preconfigured keychain is
required. Without signing credentials, local packaging produces a strictly
verified ad-hoc signed DMG.
