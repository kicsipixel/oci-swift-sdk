# functions-live-test — end-to-end OCI Functions test

A live, end-to-end exercise of the OCI Functions support in this SDK:

```
relay-invoke (local CLI, API-key auth)
      │  FunctionsInvokeClient.invokeFunction(...)
      ▼
relay-function (OCI Function, OCIKitFunctions FDK)
      │  ObjectStorageClient.getObject(...)  with Resource Principal auth
      ▼
Object Storage: reads an object and returns its contents
```

One round trip validates all of: local **API-key auth**, the **invoke client**, a Swift
program **running as a function** (the FDK), **Resource Principal auth** inside the
function, and the **Object Storage client**.

- **`relay-function`** — the function. Reads `OSS_NAMESPACE` / `OSS_BUCKET` /
  `OSS_OBJECT` from its function configuration and returns the object's bytes.
- **`relay-invoke`** — a local CLI that invokes a function by OCID and logs the reply.

> This directory is a standalone SwiftPM package that depends on `oci-swift-sdk` from
> GitHub, so nothing here is part of the SDK's own build or CI.

---

## Prerequisites

- The [OCI CLI](https://docs.oracle.com/iaas/tools/oci-cli/latest/) configured with a
  profile that has an API key (referred to below as `<profile>`).
- Docker (with `buildx`) and a Swift 6.2 toolchain.
- A bucket and a test object to read, and a **regional subnet with egress to Object
  Storage** (a public subnet with an internet gateway, or a private subnet with a
  service gateway) for the Functions application.
- Permission to create Functions, OCIR repos, dynamic groups, and policies in the
  target compartment.

## Reference values

The steps below use shell variables. Fill in the OCIDs/namespace for your tenancy;
`oci os ns get --profile <profile>` prints your Object Storage namespace.

```sh
PROFILE=<profile>                       # e.g. jroga
REGION=us-phoenix-1                      # region for the app/function
OCIR=phx.ocir.io                         # <region-key>.ocir.io
NS=<namespace>                           # Object Storage namespace (oci os ns get)
COMPARTMENT=<compartment-ocid>           # the compartment to deploy into
COMPARTMENT_NAME=<compartment-name>      # its name, used in the policy statement
SUBNET=<subnet-ocid>                     # subnet with egress to Object Storage
BUCKET=<bucket-name>                     # bucket holding the test object
OBJECT=<object-name>                     # e.g. hello.txt
IMAGE=$OCIR/$NS/relay-function:0.0.1
```

---

## 1. Build and push the function image

The function is packaged with the `Dockerfile` in this directory (multi-stage:
`swift:6.2` builder → `ubuntu:24.04` runtime with `libcurl`/`ca-certificates` and a
non-root `fn` user). Build for the architecture that matches the application shape —
`GENERIC_ARM` → `linux/arm64` here.

```sh
docker build --platform linux/arm64 -t "$IMAGE" .
```

Push to OCIR. The Docker password is an **auth token** (Console → your user → Auth
Tokens, or `oci iam auth-token create`). Treat it like a password — pass it on stdin,
never commit it, and delete it when you are done (see Teardown).

```sh
docker login "$OCIR" -u "$NS/<username>" --password-stdin   # paste the auth token
docker push "$IMAGE"
```

## 2. Create the Functions application and function

```sh
APP=$(oci fn application create \
  --compartment-id "$COMPARTMENT" --display-name relay-app \
  --subnet-ids "[\"$SUBNET\"]" --shape GENERIC_ARM \
  --profile "$PROFILE" --query 'data.id' --raw-output)

FN=$(oci fn function create \
  --application-id "$APP" --display-name relay-function \
  --image "$IMAGE" --memory-in-mbs 512 \
  --config "{\"OSS_NAMESPACE\":\"$NS\",\"OSS_BUCKET\":\"$BUCKET\",\"OSS_OBJECT\":\"$OBJECT\"}" \
  --profile "$PROFILE" --query 'data.id' --raw-output)

# The per-function invoke endpoint (needed by the client):
ENDPOINT=$(oci fn function get --function-id "$FN" \
  --profile "$PROFILE" --query 'data."invoke-endpoint"' --raw-output)
```

512 MB gives the Swift + NIO runtime headroom on cold start.

## 3. Grant the function Resource Principal access to the bucket

A running function authenticates as a **Resource Principal**. A dynamic group matches
the function, and a policy lets that dynamic group read the bucket.

```sh
oci iam dynamic-group create --name relay-fn-dg \
  --description "relay-function resource principal" \
  --matching-rule "ALL {resource.type = 'fnfunc', resource.compartment.id = '$COMPARTMENT'}" \
  --profile "$PROFILE"

oci iam policy create --compartment-id "$COMPARTMENT" --name relay-fn-oss-read \
  --description "Allow relay-function to read the test bucket" \
  --statements "[\"Allow dynamic-group relay-fn-dg to read objects in compartment $COMPARTMENT_NAME where target.bucket.name = '$BUCKET'\"]" \
  --profile "$PROFILE"
```

The caller that runs `relay-invoke` needs `use fn-invocation` on the function; members
of `Administrators` already have it, otherwise add a matching policy for their group.

> IAM changes can take a short while to propagate. If the first invoke returns a `500`
> mentioning an authorization/`404` error, wait a minute and retry.

## 4. Run the client

```sh
swift build
.build/debug/relay-invoke "$ENDPOINT" "$FN" "$PROFILE"
```

Expected output (the first call may take longer while the container cold-starts):

```
info OCIKit: [relay_invoke] invoking function ocid1.fnfunc... via https://....functions.oci.oraclecloud.com (profile: <profile>)
info OCIKit: [relay_invoke] function returned: <contents of your object>
```

`relay-invoke <invokeEndpoint> <functionOCID> [profile]` uses `APIKeySigner` +
`FunctionsInvokeClient`; the function reads the object with `ObjectStorageClient` under
Resource Principal auth and returns it.

---

## Troubleshooting

- **`502 Container failed to initialize`** — run the image locally to see the startup
  error: `docker run --rm -e FN_LISTENER=unix:/tmp/lsnr.sock -e FN_FORMAT=http-stream
  --entrypoint /function/relay-function "$IMAGE"`. A missing
  `libcurl.so.4: cannot open shared object file` means the runtime image lacks
  `libcurl4`/`ca-certificates` (the `Dockerfile` here installs them). A healthy start
  logs `OCIKitFunctions serving on …` and creates `lsnr.sock -> phonylsnr.sock`.
- **`groupadd: GID '1000' already in use`** when building — `ubuntu:24.04` ships a
  default user at uid/gid 1000; the `Dockerfile` deletes it before creating `fn`.
- **Enable function logs** (Console → the application → Logs) to see the function's
  own `logger` output for deeper debugging.

## Teardown

```sh
oci fn function delete --function-id "$FN" --force --profile "$PROFILE"
oci fn application delete --application-id "$APP" --force --profile "$PROFILE"
oci iam policy delete --policy-id "$(oci iam policy list --compartment-id "$COMPARTMENT" \
  --name relay-fn-oss-read --profile "$PROFILE" --query 'data[0].id' --raw-output)" --force --profile "$PROFILE"
oci iam dynamic-group delete --dynamic-group-id "$(oci iam dynamic-group list \
  --name relay-fn-dg --profile "$PROFILE" --query 'data[0].id' --raw-output)" --force --profile "$PROFILE"
# Also delete the OCIR repo (Console or `oci artifacts container repository delete`)
# and the auth token you created for `docker login`.
```

See [../../Sources/OCIKitFunctions/README.md](../../Sources/OCIKitFunctions/README.md)
for the full FDK guide.
