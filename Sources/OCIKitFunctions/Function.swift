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

/// A function handler closure.
///
/// Returning a ``FunctionResponse`` completes the invocation. Throwing maps to a
/// `502` framework error, and exceeding ``InvocationContext/deadline`` maps to a
/// `504`. The closure is `@Sendable` because invocations can run concurrently on a
/// single warm container.
public typealias FunctionHandler = @Sendable (
  _ context: InvocationContext,
  _ request: FunctionRequest
) async throws -> FunctionResponse

/// A type that handles function invocations.
///
/// Conform a type to `Function` when you want to keep handler state (OCI clients,
/// signers, caches) in stored properties instead of closure captures, then serve
/// it with ``FunctionRuntime/serve(_:logger:)``. Construct the instance once at
/// startup so its state is reused across invocations on a warm container.
public protocol Function: Sendable {
  /// Handles a single invocation.
  func handle(_ context: InvocationContext, _ request: FunctionRequest) async throws -> FunctionResponse
}
