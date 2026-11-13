# Releasing nanoflags-openfeature-swift

The source of truth is the NanoFlags monorepo (`packages/sdk-swift/OpenFeature`); this repository is synced from it
with `scripts/export-swift-repos.sh`.

Tags are **bare semver** — `0.1.0`, `0.2.0`, `1.0.0-rc.1` — with no `v` prefix, as Swift Package Manager expects.

1. The core package `motazalmaroai/nanoflags-swift` must already have the tag this package depends on
   (`Package.swift`: `from: "0.1.0"`). Tag and push the core first.
2. Push `main`, wait for `mobile-swift.yml` to pass (macOS `swift test`, iOS simulator `xcodebuild test`).
3. Check that the package resolves against the tagged core (not only the CI's local checkout):

   ```sh
   rm -rf .build Package.resolved && swift package resolve && swift build
   ```

4. Tag and push:

   ```sh
   git tag -a 0.1.0 -m "NanoFlags OpenFeature provider for Swift 0.1.0"
   git push origin 0.1.0
   ```

Never move or delete a published tag; release a new patch version instead.
