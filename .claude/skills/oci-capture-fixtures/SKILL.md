---
name: oci-capture-fixtures
description: Captures a real Oracle Cloud Infrastructure (OCI) wire response — and the request that produced it — into a committable JSON fixture under Tests/Services/Fixtures, using a live OCI config profile (default "DEFAULT"). Use when asked to "capture a real OCI response", "record a fixture from OCI", "capture <operation> from my <profile> profile", or "grab the real wire response" for an operation.
---

# Capture OCI wire fixtures

Record one real OCI response through the SDK's own transport, sanitize it, and
commit it so `oci-wire-tests` can replay it forever with no credentials or
network. This is a **local, one-time, credential-gated step — never run in CI**.

## 1. Confirm the target operation and that its client is seam-wired

Every service client must take `httpClient: HTTPClient = .live`
(`Sources/OCIKit/core/HTTPClient.swift`). Check the client struct for the
operation you're capturing (e.g. `IAMClient`, `ObjectStorageClient`):

```bash
grep -n "httpClient" Sources/OCIKit/services/**/*.swift
```

- If it already takes `httpClient`, skip to step 2.
- If not, wire it (3-line, backward-compatible change — the `.live` default means
  no existing caller breaks):
  1. Add a stored property: `let httpClient: HTTPClient`
  2. Add a defaulted init parameter: `httpClient: HTTPClient = .live`
  3. Assign it: `self.httpClient = httpClient`
  Then find/replace every send site in that service file:
  `- let (data, response) = try await URLSession.shared.data(for: req)`
  `+ let (data, response) = try await httpClient.data(req)`
  If the client doesn't exist yet at all, hand off to **oci-new-service-client**
  first, then come back here.

## 2. Resolve the profile's region and endpoint

Read the region from `~/.oci/config` (or `OCI_CONFIG_FILE` if set) for the given
profile (default `DEFAULT`) using `extractUserRegion` from
`Sources/OCIKit/core/Region+Service.swift`:

```swift
let region = Region.from(regionId: try extractUserRegion(from: configFile, profile: profile) ?? "") ?? .iad
```

Most clients accept `region: Region` directly and derive the real host
themselves; a few (like `ObjectStorageClient`) also accept an explicit
`endpoint:` string (e.g. `https://objectstorage.us-ashburn-1.oraclecloud.com`) —
use whichever the client's initializer exposes.

## 3. Add (or reuse) a gated capture `@Test`

Add a case to `Tests/Services/OCICaptureTests.swift` — it already self-skips
unless its env vars are set, so it's safe to leave in the tree and never runs in
CI. Follow the existing `captureGetNamespace` pattern: build the client with a
**real `APIKeySigner`** from the profile and
`httpClient: .recording(into: URL(filePath: out))`, then call the operation
(pass any required real arguments, like `compartmentId` or `namespace`, via env
vars — never hardcode them):

```swift
@Test("captures listCompartments from live OCI into a fixture")
func captureListCompartments() async throws {
  let env = ProcessInfo.processInfo.environment
  guard let out = env["OCI_FIXTURE_OUT"],
        let configFile = env["OCI_CONFIG_FILE"],
        let compartmentId = env["OCI_COMPARTMENT_ID"] else {
    logger.info("capture skipped — set OCI_FIXTURE_OUT, OCI_CONFIG_FILE, OCI_COMPARTMENT_ID")
    return
  }
  let profile = env["OCI_PROFILE"] ?? "DEFAULT"
  let signer = try APIKeySigner(configFilePath: configFile, configName: profile)
  let region = Region.from(regionId: try extractUserRegion(from: configFile, profile: profile) ?? "") ?? .iad

  let client = try IAMClient(
    region: region, signer: signer,
    httpClient: .recording(into: URL(filePath: out))   // wraps .live
  )
  _ = try await client.listCompartments(compartmentId: compartmentId)
  // writes <out>/GET_20160918_compartments.json
}
```

Run it once against the real tenancy:

```bash
OCI_CONFIG_FILE=$HOME/.oci/config OCI_PROFILE=DEFAULT \
OCI_COMPARTMENT_ID=ocid1.tenancy.oc1..aaaa… \
OCI_FIXTURE_OUT=/tmp/fixtures \
swift test --filter OCICaptureTests
```

For a client that takes an explicit `endpoint:` (like `ObjectStorageClient`
today), set `OCI_CAPTURE_BASE_URL=https://<service>.<region>.oraclecloud.com`
instead of/alongside deriving `region`; see `OCICaptureTests.captureGetNamespace`
for that shape. Operation-specific arguments (namespace, bucket, object name,
etc.) are always passed through env vars, following the same pattern.

The recording transport (`HTTPClient.recording(into:)` in
`Sources/OCIKit/core/HTTPFixture.swift`) wraps `.live`, so it captures the
response **exactly as the client sees it** — real status code, real header
casing, real body — and writes it to
`<OCI_FIXTURE_OUT>/<METHOD>_<sanitized-path>.json`.

## 4. Sanitize before committing — this step is mandatory

Open the captured JSON and scrub anything real:

- OCIDs (tenancy, compartment, user, resource) → replace the unique suffix with
  `EXAMPLE`, e.g. `ocid1.compartment.oc1..EXAMPLE`
- Tenancy/company names, email addresses, real resource names
- `opc-request-id` and any other request-id-shaped header → `EXAMPLE`
- Pre-Authenticated Request (PAR) tokens, SAS-like tokens, or any secret body
  content
- The captured `request.url` (query params can carry the same OCIDs)

Keep the **shape** intact: same JSON field names, same header keys, same
structure — only the values change. The body is stored as `bodyBase64`; decode
it, edit the JSON, re-encode:

```bash
python3 -c "import json,base64,pathlib
p = pathlib.Path('/tmp/fixtures/GET_20160918_compartments.json')
f = json.loads(p.read_text())
body = json.loads(base64.b64decode(f['bodyBase64']))
# ...edit body in place to replace real OCIDs/names with EXAMPLE...
f['bodyBase64'] = base64.b64encode(json.dumps(body).encode()).decode()
f['headers']['opc-request-id'] = 'EXAMPLE'
p.write_text(json.dumps(f, indent=2, sort_keys=True))
"
```

**Never commit an un-sanitized real response.** If in doubt, grep the file for
`ocid1.` and the tenancy name before moving on.

## 5. Move into place and verify it loads

```bash
cp /tmp/fixtures/GET_20160918_compartments.json \
   Tests/Services/Fixtures/listCompartments.json
```

Verify it decodes with `HTTPFixture.load`, e.g. from a quick swift-testing
assertion or a scratch script:

```swift
let fixture = try HTTPFixture.load(fromFile: URL(filePath: "Tests/Services/Fixtures/listCompartments.json"))
#expect(fixture.statusCode == 200)
```

## Notes

- The fixture only records `request.method` and `request.url` today (see
  `HTTPFixture.Request` in `Sources/OCIKit/core/HTTPFixture.swift`). If the
  replay test in `oci-wire-tests` needs to assert on request **headers or body**
  (not just method/path/query), extend `HTTPFixture.Request` and
  `HTTPClient.recording(into:base:)` to also capture `request.allHTTPHeaderFields`
  and `request.httpBody`, and re-capture — don't fake it by hand.
- A capture requires live OCI credentials, so it can only be run locally by a
  developer with a configured `~/.oci/config` profile. It must never be added to
  `.github/workflows/linux.yml`'s `UNIT_TEST_FILTER` — that list is for
  credential-free hermetic/replay suites only.
- Once the fixture is committed, hand off to **oci-wire-tests** to write the
  hermetic replay suite (`Tests/Services/<Service>HermeticTests.swift`) that
  loads it via `HTTPClient.replaying(fromFile:)` and asserts on request shape
  and response decoding — and to add that suite's type name to
  `UNIT_TEST_FILTER` in `.github/workflows/linux.yml` so it runs in CI.