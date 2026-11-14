# Releasing nanoflags-openfeature-swift

The source of truth is the NanoFlags monorepo (`packages/sdk-swift/OpenFeature`); this repository is synced from it
with `scripts/export-swift-repos.sh`.

Tags are **bare semver** — `0.1.0`, `0.2.0`, `1.0.0-rc.1` — with no `v` prefix, as Swift Package Manager expects.

Releases are automated by `.github/workflows/release.yml`:

1. The core package `motazalmaroai/nanoflags-swift` must already have the tag this package depends on
   (`Package.swift`: `from: "0.1.0"`); the release workflow fails until it does.
2. Add a dated `CHANGELOG.md` entry (`## 0.2.0 — 2026-12-01`) in the monorepo, export, commit, push `main`.
3. The release workflow runs the tests (macOS `swift test`, iOS simulator `xcodebuild test`) against the tagged core
   and, only if they pass, creates the tag and a GitHub release with the CHANGELOG section as notes.

Never move or delete a published tag; release a new patch version instead.
