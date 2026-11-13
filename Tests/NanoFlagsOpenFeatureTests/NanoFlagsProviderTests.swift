import Foundation
import NanoFlags
import NanoFlagsOpenFeature
import OpenFeature
import XCTest

/// Runs on macOS / iOS only (OpenFeature needs Combine): `swift test --package-path OpenFeature`.
final class NanoFlagsProviderTests: XCTestCase {
    static let bundle = """
    {"schema":1,"project":"p","environment":"e","revision":4,"segments":{},"flags":{
    "new-checkout":{"type":"boolean","enabled":true,"clientExposed":true,"default":false,"off":false,"rules":[{"id":"pro","match":"all","conditions":[{"attribute":"plan","op":"eq","value":"pro"}],"serve":{"type":"fixed","value":true}}]},
    "accent":{"type":"string","enabled":true,"clientExposed":true,"default":"blue","off":"blue","rules":[{"id":"half","match":"all","conditions":[],"serve":{"type":"rollout","percentage":50,"value":"orange","otherwise":"green"}}]},
    "limit":{"type":"number","enabled":true,"clientExposed":true,"default":3,"off":0,"rules":[]},
    "off-flag":{"type":"string","enabled":false,"clientExposed":true,"default":"a","off":"o","rules":[]},
    "theme":{"type":"json","enabled":true,"clientExposed":true,"default":{"dark":true},"off":null,"rules":[]}}}
    """

    func makeClient() -> NanoFlagsClient {
        // An unreachable edge: the bootstrap bundle is all there is (status becomes stale, values stay).
        NanoFlags.start(key: "nf_pub_test0000000000000000", options: NanoFlagsOptions(
            baseURL: URL(string: "http://127.0.0.1:9")!, transport: .polling, storage: .none, bootstrap: Data(Self.bundle.utf8), events: .disabled))
    }

    func testEvaluationsThroughOpenFeature() async throws {
        let client = makeClient()
        let provider = NanoFlagsProvider(client: client, initTimeout: 5, closeClientOnShutdown: true)
        await OpenFeatureAPI.shared.setProviderAndWait(provider: provider, initialContext: ImmutableContext(
            targetingKey: "user-1", structure: ImmutableStructure(attributes: ["plan": .string("pro")])))
        let of = OpenFeatureAPI.shared.getClient()

        let b = of.getBooleanDetails(key: "new-checkout", defaultValue: false)
        XCTAssertEqual(b.value, true)
        XCTAssertEqual(b.reason, "TARGETING_MATCH")
        XCTAssertEqual(b.variant, "pro")
        XCTAssertEqual(b.flagMetadata["revision"], .integer(4))

        let s = of.getStringDetails(key: "accent", defaultValue: "")
        XCTAssertEqual(s.reason, "SPLIT")
        XCTAssertEqual(s.value, client.stringVariation(key: "accent", default: "x"))

        XCTAssertEqual(of.getIntegerValue(key: "limit", defaultValue: 0), 3)
        XCTAssertEqual(of.getDoubleDetails(key: "limit", defaultValue: 0).reason, "DEFAULT")
        XCTAssertEqual(of.getStringDetails(key: "off-flag", defaultValue: "").reason, "DISABLED")
        XCTAssertEqual(of.getObjectValue(key: "theme", defaultValue: .null), .structure(["dark": .boolean(true)]))

        let missing = of.getBooleanDetails(key: "missing", defaultValue: true)
        XCTAssertEqual(missing.value, true)
        XCTAssertEqual(missing.errorCode, .flagNotFound)
        let mismatch = of.getBooleanDetails(key: "limit", defaultValue: false)
        XCTAssertEqual(mismatch.errorCode, .typeMismatch)

        // A new context is applied locally and synchronously.
        await OpenFeatureAPI.shared.setEvaluationContextAndWait(evaluationContext: ImmutableContext(targetingKey: "user-2"))
        XCTAssertEqual(of.getBooleanValue(key: "new-checkout", defaultValue: true), false)
        XCTAssertEqual(client.currentContext.key, "user-2")

        await OpenFeatureAPI.shared.clearProviderAndWait()
    }

    func testValueConversions() {
        XCTAssertEqual(NanoFlagsProvider.json(.list([.integer(2), .double(1.5), .null])), [2, 1.5, nil])
        XCTAssertEqual(NanoFlagsProvider.value(["a": [true, "x"]]), .structure(["a": .list([.boolean(true), .string("x")])]))
        let ctx = NanoFlagsProvider.context(ImmutableContext(targetingKey: "k", structure: ImmutableStructure(attributes: ["key": .string("other"), "n": .integer(5)])))
        XCTAssertEqual(ctx.key, "k")
        XCTAssertEqual(ctx.attributes["n"], 5)
        XCTAssertNil(ctx.attributes["key"])
    }
}
