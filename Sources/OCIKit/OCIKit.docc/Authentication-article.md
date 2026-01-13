# Authentication

Understand the different authentication methods available in OCIKit.

## Overview

OCIKit provides multiple authentication strategies through the ``Signer`` protocol. Choose the method that best fits your deployment environment.

## API Key Authentication

The most common method for local development and scripts. Uses your OCI config file with a private key.

```swift
let signer = try APIKeySigner(
  configFilePath: "~/.oci/config",
  configName: "DEFAULT"
)
```

### Configuration File Format

```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=eu-frankfurt-1
key_file=~/.oci/oci_api_key.pem
```

### Multiple Profiles

You can define multiple profiles in your config file and select one by name:

```swift
// Use the PRODUCTION profile
let signer = try APIKeySigner(
  configFilePath: "~/.oci/config",
  configName: "PRODUCTION"
)
```

## Instance Principal Authentication

Use this when running code on an OCI compute instance. The instance's identity is used for authentication - no config file needed.

```swift
let signer = try InstancePrincipalSigner()
```

The instance must be in a dynamic group with appropriate IAM policies granting access to the required resources.

### Requirements

1. Code must run on an OCI compute instance
2. Instance must be in a dynamic group
3. IAM policies must grant the dynamic group access

Example dynamic group matching rule:
```
instance.compartment.id = 'ocid1.compartment.oc1..aaaaaaa...'
```

Example policy:
```
Allow dynamic-group my-instances to manage objects in compartment my-compartment
```

## Security Token Authentication

For scenarios requiring temporary credentials or token-based authentication.

```swift
// From config file with security_token_file
let signer = try SecurityTokenSigner(
  configFilePath: "~/.oci/config",
  configName: "DEFAULT"
)

// Or with direct token
let signer = SecurityTokenSigner(
  securityToken: tokenString,
  privateKey: privateKey
)
```

## The Signer Protocol

All authentication methods implement the ``Signer`` protocol:

```swift
public protocol Signer {
  func sign(_ req: inout URLRequest) throws
}
```

This allows you to create custom authentication implementations if needed.

## Choosing an Authentication Method

| Method | Use Case |
|--------|----------|
| ``APIKeySigner`` | Local development, scripts, CI/CD pipelines |
| ``InstancePrincipalSigner`` | Applications running on OCI compute instances |
| ``SecurityTokenSigner`` | Temporary credentials, delegated auth |

## Error Handling

Authentication errors are thrown as ``ConfigErrors``:

```swift
do {
  let signer = try APIKeySigner(configFilePath: "~/.oci/config")
}
catch ConfigErrors.missingConfig {
  print("Config file not found")
}
catch ConfigErrors.missingKeyfile {
  print("Private key file not found")
}
catch ConfigErrors.badKeyfile(let message) {
  print("Invalid key file: \(message)")
}
```
