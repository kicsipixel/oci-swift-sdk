# ``OCIKit``

A Swift SDK for Oracle Cloud Infrastructure (OCI) providing async/await APIs for OCI services.

## Overview

OCIKit enables Swift applications to interact with Oracle Cloud Infrastructure services using modern async/await patterns. The SDK handles authentication, request signing, and response parsing automatically.

### Supported Services

- **Object Storage** - Store and manage objects in buckets
- **IAM** - Identity and Access Management operations
- **Secrets** - Retrieve secrets from OCI Vault
- **Language** - AI language processing services
- **Generative AI** - OCI Generative AI services

### Quick Example

```swift
import OCIKit

// Create a signer using your OCI config file
let signer = try APIKeySigner(
  configFilePath: "~/.oci/config",
  configName: "DEFAULT"
)

// Initialize a client for Object Storage
let client = try ObjectStorageClient(region: .fra, signer: signer)

// Make async API calls
let namespace = try await client.getNamespace(compartmentId: "ocid1.tenancy...")
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Authentication-article>

### Authentication

- ``Signer``
- ``APIKeySigner``
- ``InstancePrincipalSigner``
- ``SecurityTokenSigner``
- ``SignerConfiguration``

### Configuration

- ``Region``
- ``Service``
- ``ConfigErrors``

### Service Clients

- ``ObjectStorageClient``
- ``IAMClient``
- ``SecretsClient``

### Request Building

- ``API``
- ``HTTPMethod``
