# OCIKitFunctions — run Swift as an OCI Function

`OCIKitFunctions` is the **Function Development Kit (FDK)** for Swift: it lets a
compiled Swift program run as an [Oracle Cloud Infrastructure
Function](https://www.oracle.com/cloud-native/functions/) (built on
[Fn Project](https://fnproject.io)), at parity with the official `fdk-python`,
`fdk-go`, and `fdk-java`.

It is an **opt-in product** — it depends on [SwiftNIO](https://github.com/apple/swift-nio)
to serve the Fn `http-stream` contract over a Unix domain socket, so programs that
only *call* OCI (via `OCIKit`) never pull NIO in. To *invoke* an already-deployed
function from a Swift service, use [`FunctionsInvokeClient`](#invoking-a-function-from-swift)
in core `OCIKit` instead (no NIO required).

- **Runtime**: macOS + Linux (x86_64 and arm64). Functions deploy as Linux containers.
- **Auth from inside a function**: use [`ResourcePrincipalSigner`](#calling-other-oci-services-resource-principals),
  which OCI wires into the container environment automatically.

## Writing a function

Create an executable SwiftPM package that depends on `OCIKitFunctions` and calls
`FunctionRuntime.serve` from `main`:

```swift
// Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "hello-swift-fn",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/iliasaz/oci-swift-sdk.git", branch: "main"),
  ],
  targets: [
    .executableTarget(
      name: "hello-swift-fn",
      dependencies: [
        .product(name: "OCIKitFunctions", package: "oci-swift-sdk"),
        .product(name: "OCIKit", package: "oci-swift-sdk"),
      ]
    )
  ]
)
```

```swift
// Sources/hello-swift-fn/main.swift
import OCIKitFunctions

try await FunctionRuntime.serve { context, request in
  let name = request.string ?? "world"
  return .text("Hello, \(name)!")
}
```

That is a complete function. `serve` reads `FN_LISTENER`/`FN_FORMAT`, performs the
Fn "phony socket" readiness handshake, and serves the http-stream contract until the
container shuts down. Each request becomes one call to your closure.

### Request and response

`FunctionRequest` gives you the raw body plus convenience decoders:

```swift
try await FunctionRuntime.serve { context, request in
  struct Input: Decodable { let a: Int; let b: Int }
  struct Output: Encodable { let sum: Int }
  let input = try request.decode(Input.self)
  return try .json(Output(sum: input.a + input.b))
}
```

`FunctionResponse` has helpers — `.text`, `.json`, `.data`, `.empty` — or build one
directly to set a `status` and `headers` (both meaningful only for HTTP-triggered
invocations; see below).

### HTTP-triggered vs plain invocations

When a function is fronted by an **API Gateway or HTTP trigger**, the platform sets
`Fn-Intent: httprequest` and tunnels the original HTTP request. `OCIKitFunctions`
decapsulates it for you:

```swift
try await FunctionRuntime.serve { context, request in
  if context.isHTTPRequest {
    // context.httpMethod, context.requestURL, context.httpHeaders["Authorization"], …
    guard context.httpMethod == "POST" else { return .text("method not allowed", status: 405) }
  }
  return .text("ok")            // status/headers are returned to the HTTP client
}
```

For a **plain** invocation (e.g. `fn invoke`, or `FunctionsInvokeClient`) the handler
just sees the raw body, and only the response body is returned — `status`/`headers`
are ignored because there is no HTTP response channel.

### Deadlines and errors

- Each invocation carries a deadline (`context.deadline`, from `Fn-Deadline`, default
  `now + 30s`). If the handler overruns it, the FDK cancels the handler `Task` and
  returns **504**. Cancellation is cooperative — handlers doing `async` I/O stop
  promptly.
- If the handler throws, the FDK returns **502**.

### Reusing state across invocations (warm containers)

A container serves many invocations. Anything you build **before** `serve` runs once
and is captured by the handler — the idiomatic Swift equivalent of `fdk-java`'s
`@FnConfiguration`:

```swift
import OCIKit
import OCIKitFunctions

let runtime = RuntimeContext.fromEnvironment()
let signer = try runtime.resourcePrincipalSigner()          // built once per container
let objectStorage = try ObjectStorageClient(region: .iad, signer: signer)

try await FunctionRuntime.serve { context, request in
  let namespace = try await objectStorage.getNamespace()    // reuses the warm client
  return .text(namespace)
}
```

Prefer a `Function`-conforming type if you want handler state in stored properties:

```swift
struct Greeter: Function {
  let objectStorage: ObjectStorageClient
  func handle(_ context: InvocationContext, _ request: FunctionRequest) async throws -> FunctionResponse {
    .text("Hello from \(try await objectStorage.getNamespace())")
  }
}
try await FunctionRuntime.serve(Greeter(objectStorage: objectStorage))
```

## Calling other OCI services (Resource Principals)

A running function authenticates to OCI with a **Resource Principal** — OCI injects a
short-lived session token and private key into the container. `RuntimeContext`
provides a thin helper that returns the existing `OCIKit` signer:

```swift
let signer = try RuntimeContext.fromEnvironment().resourcePrincipalSigner()
let client = try FunctionsInvokeClient(invokeEndpoint: "...", signer: signer)
```

The signer transparently re-reads the token/key files and refreshes as the token
nears expiry, so a single instance is safe for the life of a warm container. Grant
the function's [dynamic group](https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsaccessingociresources.htm)
the IAM policies it needs.

## Deploying

Compiled functions use a **custom Dockerfile** (`runtime: docker`). OCI builds and
pushes your image with `fn deploy`.

### `func.yaml`

```yaml
schema_version: 20180708
name: hello-swift-fn
version: 0.0.1
runtime: docker          # build the local Dockerfile as-is
memory: 256              # 128 / 256 / 512 / 1024 / 2048 / 3072 MB
timeout: 30              # seconds (sync max 300)
triggers:
  - name: hello-swift-fn
    type: http
    source: /hello-swift-fn
```

### `Dockerfile`

A multi-stage build with a statically linked stdlib and the **mandatory non-root
`fn` user** (uid/gid 1000). Replace `hello-swift-fn` with your executable's name.

```dockerfile
# ---- build ----
FROM swift:6.2 AS build
WORKDIR /src
COPY . .
RUN swift build -c release --static-swift-stdlib \
 && install -Dm755 "$(swift build -c release --show-bin-path)/hello-swift-fn" /out/hello-swift-fn

# ---- runtime ----
FROM ubuntu:24.04
# --static-swift-stdlib bundles the Swift stdlib but NOT system C libs. A function
# that calls an OCI service uses Foundation's URLSession, which on Linux needs
# libcurl + a CA trust store, so install them (and libxml2).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libxml2 tzdata \
 && (apt-get install -y --no-install-recommends libcurl4t64 || apt-get install -y --no-install-recommends libcurl4) \
 && rm -rf /var/lib/apt/lists/*
# ubuntu:24.04 ships a default user at uid/gid 1000; remove it, then create the
# non-root fn user OCI Functions require.
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd --gid 1000 fn \
 && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin fn
COPY --from=build /out/hello-swift-fn /function/hello-swift-fn
USER fn
ENTRYPOINT ["/function/hello-swift-fn"]
```

> Without `libcurl4`/`ca-certificates` in the runtime image, a function that reaches
> an OCI service dies at startup with `libcurl.so.4: cannot open shared object file`
> and the platform reports "Container failed to initialize".

Then, from the function directory:

```sh
fn deploy --app my-app
fn invoke my-app hello-swift-fn <<< '{"name":"world"}'
```

For a multi-architecture app (`Generic_X86_ARM` shape), build and push a multi-arch
image: `docker buildx build --push --platform linux/amd64,linux/arm64/v8 -t <registry>/<repo>:<tag> .`

### Must-not-get-wrong

- The image **must** run as a non-root user (uid/gid 1000) with a writable socket
  directory — OCI restricts root containers.
- Request/response payloads are capped at ~**6 MB**; don't assume unbounded bodies.

## Invoking a function from Swift

To call a deployed function from another Swift program (an OKE service, a Container
Instance, a VM), use `FunctionsInvokeClient` from core `OCIKit` — it needs no NIO:

```swift
import OCIKit

let signer = try APIKeySigner(configFilePath: "~/.oci/config")
let client = try FunctionsInvokeClient(
  invokeEndpoint: "https://xxxxxxxx.us-ashburn-1.functions.oci.oraclecloud.com",  // the function's invokeEndpoint
  signer: signer
)
let output = try await client.invokeFunction(
  functionId: "ocid1.fnfunc.oc1.iad.aaaa...",
  body: Data(#"{"name":"world"}"#.utf8),
  contentType: "application/json"
)
logger.info("function replied: \(String(decoding: output, as: UTF8.self))")
```

The `invokeEndpoint` is the function's own endpoint (from the OCI Console, Terraform,
or `GetFunction`), not a regional endpoint. Pass `invokeType: .detached` for
fire-and-forget. Function lifecycle management (create/update/delete) is intentionally
out of scope — use Terraform, the Console, or another SDK.
