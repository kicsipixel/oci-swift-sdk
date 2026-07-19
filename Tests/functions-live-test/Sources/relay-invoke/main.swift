//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2026 Ilia Sazonov and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//
//
// A local CLI that invokes an OCI Function with API-key auth using
// FunctionsInvokeClient, and logs the function's response.
//
//   relay-invoke <invokeEndpoint> <functionOCID> [profile]
//

import Foundation
import OCIKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
  logger.error("usage: relay-invoke <invokeEndpoint> <functionOCID> [profile]")
  exit(2)
}
let invokeEndpoint = arguments[1]
let functionId = arguments[2]
let profile = arguments.count >= 4 ? arguments[3] : "DEFAULT"

let signer = try APIKeySigner(configFilePath: "~/.oci/config", configName: profile)
let client = try FunctionsInvokeClient(invokeEndpoint: invokeEndpoint, signer: signer)

logger.info("invoking function \(functionId) via \(invokeEndpoint) (profile: \(profile))")
let output = try await client.invokeFunction(functionId: functionId)
logger.info("function returned: \(String(decoding: output, as: UTF8.self))")
