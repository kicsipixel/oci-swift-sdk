# Getting Started with OCIKit

Learn how to set up and use OCIKit to interact with Oracle Cloud Infrastructure.

## Overview

This guide walks you through installing OCIKit, configuring authentication, and making your first API call to OCI services.

## Installation

Add OCIKit to your Swift package dependencies:

```swift
dependencies: [
  .package(url: "https://github.com/iliasaz/oci-swift-sdk.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
  name: "YourApp",
  dependencies: ["OCIKit"]
)
```

## Prerequisites

Before using OCIKit, ensure you have:

1. An Oracle Cloud Infrastructure account
2. An OCI configuration file at `~/.oci/config`
3. A PEM private key file referenced in your config

Your OCI config file should look like:

```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=eu-frankfurt-1
key_file=~/.oci/oci_api_key.pem
```

## Your First API Call

Here's a complete example that lists buckets in Object Storage:

```swift
import OCIKit

// 1. Create a signer for authentication
let signer = try APIKeySigner(
  configFilePath: "~/.oci/config",
  configName: "DEFAULT"
)

// 2. Initialize the Object Storage client
let client = try ObjectStorageClient(
  region: .fra,
  signer: signer
)

// 3. Get the namespace (required for most operations)
let namespace = try await client.getNamespace(
  compartmentId: "ocid1.tenancy.oc1..your-tenancy-id"
)

// 4. List buckets in a compartment
let buckets = try await client.listBuckets(
  namespaceName: namespace,
  compartmentId: "ocid1.compartment.oc1..your-compartment-id"
)

for bucket in buckets {
  print("Bucket: \(bucket.name)")
}
```

## Working with Secrets

Retrieve secrets from OCI Vault:

```swift
import OCIKit

let signer = try APIKeySigner(
  configFilePath: "~/.oci/config",
  configName: "DEFAULT"
)

let client = try SecretsClient(
  region: .fra,
  signer: signer
)

let secretBundle = try await client.getSecretBundleByName(
  secretName: "my-secret",
  vaultId: "ocid1.vault.oc1..your-vault-id"
)
```

## Choosing a Region

OCIKit supports 40+ OCI regions using airport code abbreviations:

| Region | Code |
|--------|------|
| Frankfurt | `.fra` |
| Ashburn | `.iad` |
| Phoenix | `.phx` |
| London | `.lhr` |
| Sydney | `.syd` |
| Tokyo | `.nrt` |

## Next Steps

- Learn about different <doc:Authentication-article> methods
- Explore the ``ObjectStorageClient`` for object operations
- Use ``IAMClient`` for identity management
- Retrieve secrets with ``SecretsClient``
