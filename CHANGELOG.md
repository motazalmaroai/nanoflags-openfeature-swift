# Changelog

## 0.1.0 — 2026-11-14

First release of the NanoFlags OpenFeature provider for Swift (OpenFeature Swift SDK 0.7, iOS 15+ / macOS 12+).

- `NanoFlagsProvider`: boolean, string, integer, double and object evaluations through the NanoFlags Swift SDK
  (`nanoflags-swift` from 0.1.0), with OpenFeature reasons, variants and error codes.
- Context changes call `identify`; flag changes and readiness are emitted as OpenFeature provider events.
