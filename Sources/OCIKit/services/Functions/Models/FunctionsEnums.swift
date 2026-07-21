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

import Foundation

/// How Oracle Functions should execute an invocation, sent as the `fn-invoke-type`
/// request header of ``FunctionsInvokeClient/invokeFunction(functionId:body:contentType:invokeType:intent:isDryRun:opcRequestId:)``.
public enum FunctionInvokeType: String, Sendable, Codable {
  /// Execute the request and return the result of the execution (the default).
  case sync
  /// Return as soon as processing has begun and leave result handling to the function.
  case detached
}

/// An optional hint to the receiving function's FDK about how the event body
/// should be interpreted, sent as the `fn-intent` request header.
///
/// `httprequest` marks an HTTP-gateway/trigger invocation whose body and headers
/// encapsulate an original client HTTP request; `cloudevent` marks a CloudEvents
/// payload. When omitted the function receives the body as a plain invocation.
public enum FunctionIntent: String, Sendable, Codable {
  case httprequest
  case cloudevent
}
