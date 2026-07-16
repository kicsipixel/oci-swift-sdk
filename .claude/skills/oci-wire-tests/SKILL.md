---
name: oci-wire-tests
description: Write a hermetic wire-test suite for an OCI service client from committed JSON fixtures — offline replay tests that assert request-building and response-decoding with no credentials or network. Use for "write wire tests for <service>", "add replay tests", "turn these fixtures into tests", "hermetic tests for <operation>".
---

# OCI wire tests

Turn committed `Tests/Services/Fixtures/*.json` fixtures into a fast, offline
`swift-testing` suite that runs in CI and on fork PRs with **no** `~/.oci/config`,
credentials, or network access. Full background: `docs/hermetic-wire-tests.md`.

## 1. Confirm the fixtures exist

Check `Tests/Services/Fixtures/` for the operation(s) you're testing (e.g.
`listCompartments.json`). If they're missing, or the target service client
doesn't yet take `httpClient: HTTPClient = .live` (grep the service file for
`httpClient`), **stop and hand off to the `oci-capture-fixtures` skill** to wire
the seam and capture the response first. Don't hand-write fixture JSON from
guesswork — fixtures must come from a real captured response so header casing
and field shapes are authentic. If the service client itself doesn't exist yet,
hand off to `oci-new-service-client` instead.

## 2. Create `Tests/Services/<Service>HermeticTests.swift`

Follow the `ObjectStorageHermeticTests.swift` pattern exactly:

```swift
import Foundation
import OCIKit
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// No-op signer — these tests exercise request building and response parsing,
// not signature correctness.
private struct StubSigner: Signer {
  func sign(_ req: inout URLRequest) throws {}
}

struct <Service>HermeticTests {
  private func fixtureURL(_ name: String) -> URL {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
  }

  // RESPONSE-DECODE test: replay a captured 200 and assert on the decoded model.
  @Test("listCompartments decodes the array from a captured response")
  func listCompartments() async throws {
    let http = try HTTPClient.replaying(fromFile: fixtureURL("listCompartments.json"))
    let client = try <Service>Client(region: .iad, signer: StubSigner(), httpClient: http)

    let items = try await client.listCompartments(compartmentId: "ocid1.tenancy.oc1..EXAMPLE")

    #expect(!items.isEmpty)
    #expect(items.first?.lifecycleState == .active)
  }

  // ERROR-PATH test: a non-2xx fixture maps to the service's Error type.
  @Test("listCompartments: non-2xx maps to <Service>Error")
  func errorMapping() async throws {
    let http = try HTTPClient.replaying(fromFile: fixtureURL("listCompartments_404.json"))
    let client = try <Service>Client(region: .iad, signer: StubSigner(), httpClient: http)

    await #expect(throws: <Service>Error.self) {
      _ = try await client.listCompartments(compartmentId: "ocid1.tenancy.oc1..EXAMPLE")
    }
  }
}
```

To also lock the **request shape** (method, path, query, body) instead of
replaying a fixture, use the recorder pattern from `ObjectStorageHermeticTests.swift`
— an `actor RequestRecorder` plus a hand-rolled `HTTPClient` closure that records
the request and returns a canned `HTTPURLResponse`:

```swift
private actor RequestRecorder {
  private(set) var last: URLRequest?
  func record(_ request: URLRequest) { last = request }
}

// … inside a @Test:
let recorder = RequestRecorder()
let http = HTTPClient { request in
  await recorder.record(request)
  let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
  return (Data("[]".utf8), response)
}
let client = try <Service>Client(region: .iad, signer: StubSigner(), httpClient: http)
_ = try await client.listCompartments(compartmentId: "ocid1.tenancy.oc1..EXAMPLE", limit: 10)

let req = await recorder.last
#expect(req?.url?.path == "/20160918/compartments")
let query = Dictionary(uniqueKeysWithValues:
  (URLComponents(url: req!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
#expect(query["compartmentId"] == "ocid1.tenancy.oc1..EXAMPLE")
#expect(query["limit"] == "10")
```

Write one response-decode test per operation you're covering, plus at least one
error-mapping test per client (non-2xx fixtures are cheap — either capture a real
one or hand-edit a captured fixture's `statusCode`/`bodyBase64`). Use request-shape
tests where query params, path segments, or the body matter.

## 3. Register the suite in CI

CI only runs suites listed in `UNIT_TEST_FILTER` (`.github/workflows/linux.yml`),
even though the build step compiles everything. Append the new type name to the
pipe-separated list:

```yaml
UNIT_TEST_FILTER: >-
  …|ObjectStorageHermeticTests|OCIFixtureReplayTests|<Service>HermeticTests
```

## 4. Run and verify

```bash
swift test --filter <Service>HermeticTests            # macOS, milliseconds

# Then verify on Linux (header casing differs from Darwin — this is where
# case-sensitive dictionary lookups on HTTPURLResponse headers break):
docker run --rm --platform linux/arm64 -v "$PWD":/pkg -w /pkg swift:6.2 \
  swift test --filter <Service>HermeticTests
```

Also cross-check x86_64 by opening a PR and watching the `linux.yml` matrix (it
runs both `ubuntu-latest` and `ubuntu-24.04-arm`).

## What wire tests cover — and what they don't

**Covered:** the request the client builds (method, path, query, body), that the
signing path is reached (`StubSigner` stamps a header the test can assert on),
response decoding (JSON shapes, RFC3339 dates, enums), error mapping for non-2xx
responses, and Linux-specific behavior like `HTTPURLResponse` header-name casing
via `value(forHTTPHeaderField:)`.

**Not covered:** whether OCI actually accepts the request — real auth, IAM
permissions, quota, and any server-side validation. A green hermetic suite proves
the SDK is internally consistent, not that it works against a live tenancy. Keep
(or add) a small credential-gated live suite for that, following the self-skip
pattern (`GenAITest`, `HealthEntityTest`) — guard on the required env var and
return early rather than relying on `try?` alone.

If fixtures go stale (OCI changes a response shape), re-run `oci-capture-fixtures`
to refresh them; don't hand-edit captured JSON beyond sanitizing OCIDs/names or
tweaking `statusCode` for an error-path test.