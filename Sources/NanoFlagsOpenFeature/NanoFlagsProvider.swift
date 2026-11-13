// NanoFlags provider for the OpenFeature Swift SDK. Apple platforms only (the SDK uses Combine): NOT
// compiled by the Linux build of this repository; the macOS CI job builds and tests it. The mapping itself
// (reasons, variants, error codes, context) is `NanoFlagsClient.openFeatureResolve` in the NanoFlags
// package, which is tested on Linux too.
import Combine
import Foundation
import NanoFlags
import OpenFeature

public struct NanoFlagsProviderMetadata: ProviderMetadata {
    public var name: String? = "nanoflags"
    public init() {}
}

/// Evaluates locally with a `NanoFlagsClient` — no network call per evaluation — and turns the client's
/// status and updates into provider events.
///
///     let provider = NanoFlagsProvider(client: NanoFlags.start(key: "nf_pub_…"))
///     await OpenFeatureAPI.shared.setProviderAndWait(provider: provider,
///                                                    initialContext: ImmutableContext(targetingKey: "user-42"))
///     let on = OpenFeatureAPI.shared.getClient().getBooleanValue(key: "new-checkout", defaultValue: false)
///
/// Mapping: the targeting key becomes the NanoFlags `key` (bucketing identity); off → DISABLED,
/// default → DEFAULT, fixed-value rule → TARGETING_MATCH, rollout → SPLIT; variant = rule id; flag metadata
/// `revision` (and `ruleIndex`). Errors: PROVIDER_NOT_READY (nothing loaded), FLAG_NOT_FOUND, TYPE_MISMATCH,
/// GENERAL. Events: READY, STALE, ERROR (first load failed), CONFIGURATION_CHANGED (with the changed flags),
/// CONTEXT_CHANGED.
public final class NanoFlagsProvider: FeatureProvider, @unchecked Sendable {
    public var hooks: [any Hook] { [] }
    public let metadata: ProviderMetadata = NanoFlagsProviderMetadata()
    public let client: NanoFlagsClient

    private let statusTracker = ProviderStatusTracker()
    private let initTimeout: TimeInterval
    private let closeClient: Bool
    private let lock = NSLock()
    private var subscriptions: [NanoFlagsSubscription] = []

    /// - Parameters:
    ///   - initTimeout: how long `initialize` waits for the first configuration.
    ///   - closeClientOnShutdown: close the client when the provider shuts down (default: the client is yours).
    public init(client: NanoFlagsClient, initTimeout: TimeInterval = 10, closeClientOnShutdown: Bool = false) {
        self.client = client
        self.initTimeout = initTimeout
        closeClient = closeClientOnShutdown
    }

    /// Starts its own client (closed on shutdown).
    public convenience init(key: String, options: NanoFlagsOptions = NanoFlagsOptions(), initTimeout: TimeInterval = 10) {
        self.init(client: NanoFlags.start(key: key, options: options), initTimeout: initTimeout, closeClientOnShutdown: true)
    }

    public var status: ProviderStatus { statusTracker.status }

    public func observe() -> AnyPublisher<ProviderEvent, Never> { statusTracker.observe() }

    // MARK: Lifecycle

    public func initialize(initialContext: EvaluationContext?) -> Future<Void, Never> {
        if let initialContext { client.identify(context: Self.context(initialContext)) }
        subscribe()
        let client = self.client
        let tracker = statusTracker
        let timeout = initTimeout
        return Future { promise in
            Task {
                let loaded = await client.ready(timeout: timeout)
                if loaded {
                    tracker.send(client.status == .stale ? .stale(nil) : .ready(nil))
                } else {
                    tracker.send(.error(ProviderEventDetails(message: "NanoFlags has no configuration loaded yet.", errorCode: .providerNotReady)))
                }
                promise(.success(()))
            }
        }
    }

    public func onContextSet(oldContext: EvaluationContext?, newContext: EvaluationContext) -> Future<Void, Never> {
        // Local and synchronous: nothing to reconcile over the network.
        client.identify(context: Self.context(newContext))
        statusTracker.send(.contextChanged(nil))
        return Future { $0(.success(())) }
    }

    public func shutdown() -> Future<Void, Never> {
        lock.lock()
        let subs = subscriptions
        subscriptions = []
        lock.unlock()
        subs.forEach { $0.cancel() }
        if closeClient { client.close() }
        return Future { $0(.success(())) }
    }

    private func subscribe() {
        lock.lock()
        defer { lock.unlock() }
        guard subscriptions.isEmpty else { return }
        let tracker = statusTracker
        let client = self.client
        subscriptions = [
            client.onStatusChange { status in
                switch status {
                case .ready: tracker.send(.ready(nil))
                case .stale: tracker.send(.stale(nil))
                case .notReady: break
                }
            },
            client.onChange { change in
                guard change.source != .context, change.previousRevision != nil else { return }
                tracker.send(.configurationChanged(ProviderEventDetails(
                    flagsChanged: change.changedFlags,
                    message: "Revision \(change.revision.map(String.init) ?? "-") is now in use.")))
            },
        ]
    }

    // MARK: Evaluation

    public func getBooleanEvaluation(key: String, defaultValue: Bool, context: EvaluationContext?) throws -> ProviderEvaluation<Bool> {
        try evaluation(client.openFeatureResolve(key: key, default: defaultValue, context: context.map(Self.context)), key) { $0 }
    }

    public func getStringEvaluation(key: String, defaultValue: String, context: EvaluationContext?) throws -> ProviderEvaluation<String> {
        try evaluation(client.openFeatureResolve(key: key, default: defaultValue, context: context.map(Self.context)), key) { $0 }
    }

    public func getIntegerEvaluation(key: String, defaultValue: Int64, context: EvaluationContext?) throws -> ProviderEvaluation<Int64> {
        try evaluation(client.openFeatureResolve(key: key, default: Int(defaultValue), context: context.map(Self.context)), key) { Int64($0) }
    }

    public func getDoubleEvaluation(key: String, defaultValue: Double, context: EvaluationContext?) throws -> ProviderEvaluation<Double> {
        try evaluation(client.openFeatureResolve(key: key, default: defaultValue, context: context.map(Self.context)), key) { $0 }
    }

    public func getObjectEvaluation(key: String, defaultValue: Value, context: EvaluationContext?) throws -> ProviderEvaluation<Value> {
        try evaluation(client.openFeatureResolve(key: key, default: Self.json(defaultValue), context: context.map(Self.context)), key) { Self.value($0) }
    }

    private func evaluation<T: FlagValue, R>(_ r: OpenFeatureResolution<T>, _ key: String, _ convert: (T) -> R) throws -> ProviderEvaluation<R> {
        if let error = r.error {
            switch error {
            case .providerNotReady: throw OpenFeatureError.providerNotReadyError
            case .flagNotFound: throw OpenFeatureError.flagNotFoundError(key: key)
            case .typeMismatch: throw OpenFeatureError.typeMismatchError
            case .general: throw OpenFeatureError.generalError(message: r.errorMessage ?? "evaluation error")
            }
        }
        var metadata: [String: FlagMetadataValue] = ["revision": .integer(Int64(r.revision))]
        if let i = r.ruleIndex { metadata["ruleIndex"] = .integer(Int64(i)) }
        return ProviderEvaluation(value: convert(r.value), flagMetadata: metadata, variant: r.variant, reason: r.reason)
    }

    // MARK: Conversions

    /// An OpenFeature evaluation context as a NanoFlags context (targeting key → `key`).
    public static func context(_ ctx: EvaluationContext) -> NanoFlagsContext {
        NanoFlagsContext.openFeature(targetingKey: ctx.getTargetingKey(), attributes: ctx.asMap().mapValues(json))
    }

    public static func json(_ v: Value) -> JSONValue {
        switch v {
        case .boolean(let b): return .bool(b)
        case .string(let s): return .string(s)
        case .integer(let i): return .number(Double(i))
        case .double(let d): return .number(d)
        case .date(let d): return .string(ISO8601DateFormatter().string(from: d))
        case .list(let l): return .array(l.map(json))
        case .structure(let s): return .object(s.mapValues(json))
        case .null: return .null
        }
    }

    /// Numbers become `.double` (NanoFlags numbers are IEEE-754 doubles, as in JavaScript).
    public static func value(_ v: JSONValue) -> Value {
        switch v {
        case .null: return .null
        case .bool(let b): return .boolean(b)
        case .number(let n): return .double(n)
        case .string(let s): return .string(s)
        case .array(let a): return .list(a.map(value))
        case .object(let o): return .structure(o.mapValues(value))
        }
    }
}
