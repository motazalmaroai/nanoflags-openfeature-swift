# NanoFlags OpenFeature provider for Swift

An [OpenFeature](https://openfeature.dev) provider for the [OpenFeature Swift SDK](https://github.com/open-feature/swift-sdk)
(0.7.x), backed by the [NanoFlags Swift SDK](https://github.com/motazalmaroai/nanoflags-swift): flags are evaluated
on the device, locally and synchronously, from a signed, live-updated configuration.

- iOS 15+, macOS 12+, tvOS 15+, watchOS 8+ (OpenFeature needs Combine, so Apple platforms only)
- Swift 6.1+ (Xcode 16.3+), as required by OpenFeature 0.7
- Version 0.1.0 · Apache-2.0

## Install

```swift
.package(url: "https://github.com/motazalmaroai/nanoflags-openfeature-swift.git", from: "0.1.0")
// target dependency:
.product(name: "NanoFlagsOpenFeature", package: "nanoflags-openfeature-swift")
```

Releases are tagged with bare semver (`0.1.0`). The package depends
on `https://github.com/motazalmaroai/nanoflags-swift` from 0.1.0.

## Use

Use the environment's **browser/mobile key** (`nf_pub_…`); the SDK refuses server keys.

```swift
import NanoFlags
import NanoFlagsOpenFeature
import OpenFeature

let provider = NanoFlagsProvider(client: NanoFlags.start(key: "nf_pub_…"))
await OpenFeatureAPI.shared.setProviderAndWait(provider: provider, initialContext: ImmutableContext(targetingKey: "user-42"))
let on = OpenFeatureAPI.shared.getClient().getBooleanValue(key: "new-checkout", defaultValue: false)
```

Mapping (as in the NanoFlags Go, Python and JavaScript providers): targeting key → NanoFlags `key`; off →
`DISABLED`, default → `DEFAULT`, fixed rule → `TARGETING_MATCH`, rollout → `SPLIT`; variant = rule id; metadata
`revision`, `ruleIndex`; errors `PROVIDER_NOT_READY`, `FLAG_NOT_FOUND`, `TYPE_MISMATCH`, `GENERAL`; events READY,
STALE, ERROR, CONFIGURATION_CHANGED (with the changed flags), CONTEXT_CHANGED.

See the [NanoFlags Swift SDK README](https://github.com/motazalmaroai/nanoflags-swift#readme) for the client options,
live updates, persistence and lifecycle, and https://nanoflags.io/docs/ios for the documentation.

## Development

```sh
swift test
```

CI (`.github/workflows/mobile-swift.yml`) checks out `nanoflags-swift` (main) next to this package and tests against
that local checkout, so the provider is always tested with the current core, tagged or not.
