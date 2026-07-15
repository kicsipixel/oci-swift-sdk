# Hermetic wire tests: capture once, replay forever

This guide shows how to add a **hermetic wire test** for an OCI operation — a test
that runs with **no `~/.oci/config`, no credentials, and no network**, so it passes
in CI and on fork PRs. The workflow is:

1. **Capture** a real OCI response once, through the SDK's own transport.
2. **Commit** it as a JSON fixture.
3. **Replay** it forever in a fast, deterministic test.

We'll use `IAMClient.listCompartments` as the example.

The building blocks already exist:

- `HTTPClient` — an injectable transport (`Sources/OCIKit/core/HTTPClient.swift`).
  Every service client takes `httpClient: HTTPClient = .live`.
- `HTTPClient.recording(into:)` / `.replaying(fromFile:)` and `HTTPFixture`
  (`Sources/OCIKit/core/HTTPFixture.swift`).

---

## Step 1 — Wire the service client with the seam (one-time per service)

`ObjectStorageClient` is already wired; `IAMClient` isn't yet. It's a three-line,
backward-compatible change (the `.live` default means every existing caller is
unchanged).

In `Sources/OCIKit/services/Identity and Access Management/IAM.swift`:

```swift
public struct IAMClient: Sendable {
  let endpoint: URL?
  let signer: Signer
  let logger: Logger
  let httpClient: HTTPClient                                   // 1. stored property

  public init(
    region: Region? = nil, endpoint: String? = nil, signer: Signer,
    retryConfig: RetryConfig? = nil, logger: Logger = Logger(label: "IAMClient"),
    httpClient: HTTPClient = .live                             // 2. defaulted parameter
  ) throws {
    // …existing assignments…
    self.httpClient = httpClient                              // 3. assignment
  }
```

Then route the send sites through it — one mechanical find/replace in `IAM.swift`:

```swift
- let (data, response) = try await URLSession.shared.data(for: req)
+ let (data, response) = try await httpClient.data(req)
```

That's the whole per-service cost. Everything below is per-test.

---

## Step 2 — Capture a real `listCompartments` response

Point the SDK at real OCI with a **recording** transport. Add a case to the gated
capture tool (`Tests/Services/OCICaptureTests.swift`) or run a one-off:

```swift
@Test func captureListCompartments() async throws {
  let env = ProcessInfo.processInfo.environment
  guard let out = env["OCI_FIXTURE_OUT"],
        let configFile = env["OCI_CONFIG_FILE"],
        let compartmentId = env["OCI_COMPARTMENT_ID"] else {
    print("capture skipped — set OCI_FIXTURE_OUT, OCI_CONFIG_FILE, OCI_COMPARTMENT_ID")
    return
  }
  let signer = try APIKeySigner(configFilePath: configFile,
                                configName: env["OCI_PROFILE"] ?? "DEFAULT")
  let region = Region.from(regionId: try extractUserRegion(from: configFile) ?? "") ?? .iad

  let client = try IAMClient(
    region: region, signer: signer,
    httpClient: .recording(into: URL(filePath: out))          // wraps .live
  )
  _ = try await client.listCompartments(compartmentId: compartmentId)
  // writes <out>/GET_20160918_compartments.json
}
```

Run it once against your tenancy:

```bash
OCI_CONFIG_FILE=$HOME/.oci/config OCI_PROFILE=DEFAULT \
OCI_COMPARTMENT_ID=ocid1.tenancy.oc1..aaaa… \
OCI_FIXTURE_OUT=/tmp/fixtures \
swift test --filter OCICaptureTests
```

The recording transport captures the response **exactly as the client sees it** —
status, body, and the true response header names OCI returns — because it records
through the same `URLSession` the SDK uses.

---

## Step 3 — Commit (and sanitize) the fixture

Move the captured file next to the tests and **review it before committing** — real
compartment responses contain OCIDs and names you may not want in the repo.

```bash
cp /tmp/fixtures/GET_20160918_compartments.json \
   Tests/Services/Fixtures/listCompartments.json
```

A trimmed, sanitized fixture:

```json
{
  "request": { "method": "GET", "url": "https://identity.us-ashburn-1.oraclecloud.com/20160918/compartments?compartmentId=ocid1.tenancy.oc1..EXAMPLE" },
  "statusCode": 200,
  "headers": { "Content-Type": "application/json", "opc-request-id": "EXAMPLE" },
  "bodyBase64": "…base64 of the JSON array of compartments…"
}
```

> The body is base64 so binary payloads (e.g. `getObject`) work too. To edit a JSON
> body by hand, decode `bodyBase64`, change it, re-encode.

---

## Step 4 — Write the hermetic replay test

In `Tests/Services/IAMHermeticTests.swift` (a `no-op` signer avoids needing a key):

```swift
import Foundation
import OCIKit
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private struct StubSigner: Signer { func sign(_ req: inout URLRequest) throws {} }

struct IAMHermeticTests {
  private func fixtureURL(_ name: String) -> URL {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
  }

  @Test("listCompartments builds GET /20160918/compartments and decodes the array")
  func listCompartments() async throws {
    let http = try HTTPClient.replaying(fromFile: fixtureURL("listCompartments.json"))
    let client = try IAMClient(region: .iad, signer: StubSigner(), httpClient: http)

    let compartments = try await client.listCompartments(
      compartmentId: "ocid1.tenancy.oc1..EXAMPLE",
      limit: 10
    )

    // Response decoding
    #expect(!compartments.isEmpty)
    #expect(compartments.allSatisfy { $0.id.hasPrefix("ocid1.compartment") })
    #expect(compartments.first?.lifecycleState == .active)
  }
}
```

Want to lock the **request shape** too (path + query), like the ObjectStorage
tests? Capture the outgoing request with an `actor RequestRecorder` and a custom
transport, or add a request assertion via the recorder pattern in
`ObjectStorageHermeticTests.swift`. For `listCompartments` you'd assert:

```swift
#expect(req?.url?.path == "/20160918/compartments")
#expect(query["compartmentId"] == "ocid1.tenancy.oc1..EXAMPLE")
#expect(query["limit"] == "10")
```

Run it — no credentials, no network:

```bash
swift test --filter IAMHermeticTests   # passes in ~milliseconds on macOS and Linux
```

---

## Step 5 — Run it in CI

Add the new suite's type name to `UNIT_TEST_FILTER` in
`.github/workflows/linux.yml` so CI executes it (the build step already compiles
it):

```yaml
UNIT_TEST_FILTER: >-
  …|ObjectStorageHermeticTests|OCIFixtureReplayTests|IAMHermeticTests
```

---

## Notes

- **Why capture instead of hand-writing JSON?** You get the true field names,
  header casing, and shapes OCI actually returns — no guessing. Replaying on Linux
  then exercises swift-corelibs-foundation's header handling against those real
  names, which is how cross-platform response-parsing bugs surface.
- **Fixtures are snapshots.** When OCI changes a response, re-capture (Step 2 is a
  one-liner). On CI, keep `swift test` in verify mode — never auto-record.
- **Sanitize.** Response bodies can carry OCIDs, tenancy names, and tags. The
  fixture stores only the *response* (auth lives in the request), but still review
  bodies before committing.
- **What this does NOT cover.** A green replay proves the SDK builds the right
  request and parses the response correctly — not that OCI accepts it (auth,
  permissions, live behavior). Keep a small credential-gated live suite for that.
