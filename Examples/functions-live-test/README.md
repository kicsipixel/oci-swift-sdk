# functions-live-test — end-to-end OCI Functions test

A live, end-to-end exercise of the OCI Functions support:

```
relay-invoke (local CLI, API-key auth)
      │  FunctionsInvokeClient.invokeFunction(...)
      ▼
relay-function (OCI Function, OCIKitFunctions FDK)
      │  ObjectStorageClient.getObject(...)  with Resource Principal auth
      ▼
Object Storage: reads swift-oke-test.txt and returns its contents
```

It validates, in one round trip: local API-key auth, the invoke client, a Swift
program running as a function (the FDK), Resource Principal auth inside the function,
and the Object Storage client.

- **`relay-function`** — the function. Reads `OSS_NAMESPACE`/`OSS_BUCKET`/`OSS_OBJECT`
  from its function configuration and returns the object's bytes.
- **`relay-invoke`** — a local CLI that invokes a function by OCID and logs the reply.

## Run the client

```sh
swift build
.build/debug/relay-invoke <invokeEndpoint> <functionOCID> <profile>
# e.g. .build/debug/relay-invoke \
#   https://xxxxxxxx.us-phoenix-1.functions.oci.oraclecloud.com \
#   ocid1.fnfunc.oc1.phx.aaaa... jroga
```

Get `<invokeEndpoint>` and `<functionOCID>` from `oci fn function get --function-id …`.

## Deploy the function (oci CLI)

Build and push the image (matching the application's shape — ARM here), then create
the function and wire up Resource Principal access. Replace the placeholders.

```sh
# 1. Image (see Dockerfile) -> OCIR
docker build --platform linux/arm64 -t <region-key>.ocir.io/<namespace>/relay-function:0.0.1 .
docker login <region-key>.ocir.io -u '<namespace>/<username>'      # password: an auth token
docker push <region-key>.ocir.io/<namespace>/relay-function:0.0.1

# 2. Application (on a subnet with egress to Object Storage) + function
oci fn application create --compartment-id <compartment> --display-name relay-app \
  --subnet-ids '["<subnet>"]' --shape GENERIC_ARM
oci fn function create --application-id <app> --display-name relay-function \
  --image <region-key>.ocir.io/<namespace>/relay-function:0.0.1 --memory-in-mbs 512 \
  --config '{"OSS_NAMESPACE":"<namespace>","OSS_BUCKET":"<bucket>","OSS_OBJECT":"<object>"}'

# 3. Resource Principal access for the function
oci iam dynamic-group create --name relay-fn-dg \
  --matching-rule "ALL {resource.type = 'fnfunc', resource.compartment.id = '<compartment>'}"
oci iam policy create --compartment-id <compartment> --name relay-fn-oss-read \
  --statements '["Allow dynamic-group relay-fn-dg to read objects in compartment <compartment-name> where target.bucket.name = '"'"'<bucket>'"'"'"]'
```

The caller (whoever runs `relay-invoke`) needs `use fn-invocation` on the function
(members of `Administrators` already have it).

See [../../Sources/OCIKitFunctions/README.md](../../Sources/OCIKitFunctions/README.md)
for the full FDK guide.
