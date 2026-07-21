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

/// The Unix domain socket the FDK must listen on, parsed from `FN_LISTENER`.
///
/// The Fn platform requires the "phony socket" readiness dance: the FDK binds a
/// listening socket at a sibling *phony* path, `chmod`s it to `0666`, and only then
/// creates a **relative** symlink at the real ``socketPath``. The atomic appearance
/// of that symlink — already listening and world-writable — is how the platform
/// detects that the container is ready. Binding ``socketPath`` directly races that
/// detection.
///
/// For `FN_LISTENER=unix:/tmp/iofs/lsnr.sock`:
/// - ``socketPath`` is `/tmp/iofs/lsnr.sock`
/// - ``phonyPath`` is `/tmp/iofs/phonylsnr.sock`
/// - ``symlinkTarget`` is `phonylsnr.sock` (relative)
public struct FnListener: Sendable, Equatable {
  /// The real socket path the platform connects to (the value of `FN_LISTENER`
  /// with its `unix:` scheme stripped).
  public let socketPath: String

  public init(socketPath: String) {
    self.socketPath = socketPath
  }

  /// The directory containing ``socketPath`` (with a trailing `/`), or `""` if none.
  private var directory: String {
    guard let slash = socketPath.lastIndex(of: "/") else { return "" }
    return String(socketPath[...slash])
  }

  /// The file name of ``socketPath``.
  private var baseName: String {
    guard let slash = socketPath.lastIndex(of: "/") else { return socketPath }
    return String(socketPath[socketPath.index(after: slash)...])
  }

  /// The sibling path the server actually binds, `phony` + the real base name.
  public var phonyPath: String {
    directory + "phony" + baseName
  }

  /// The **relative** symlink target created at ``socketPath`` — the phony base name.
  public var symlinkTarget: String {
    "phony" + baseName
  }

  /// Parses an `FN_LISTENER` value (e.g. `unix:/tmp/iofs/lsnr.sock`).
  ///
  /// The exact literal `unix:` prefix is stripped; the remaining path must be
  /// non-empty. (fdk-python's `lstrip("unix:")` is intentionally not mirrored — it
  /// over-strips leading `u/n/i/x/:` characters.)
  ///
  /// - Throws: ``FunctionRuntimeError/invalidListener(_:)`` if the value is not a
  ///   `unix:`-scheme address with a non-empty path.
  public static func parse(_ raw: String) throws -> FnListener {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "unix:"
    guard trimmed.hasPrefix(prefix) else {
      throw FunctionRuntimeError.invalidListener(raw)
    }
    let path = String(trimmed.dropFirst(prefix.count))
    guard !path.isEmpty else {
      throw FunctionRuntimeError.invalidListener(raw)
    }
    return FnListener(socketPath: path)
  }

  /// Parses the `FN_LISTENER` value from an environment dictionary.
  ///
  /// - Throws: ``FunctionRuntimeError/missingListener`` if `FN_LISTENER` is absent,
  ///   or ``FunctionRuntimeError/invalidListener(_:)`` if it is malformed.
  public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> FnListener {
    guard let raw = environment["FN_LISTENER"], !raw.isEmpty else {
      throw FunctionRuntimeError.missingListener
    }
    return try parse(raw)
  }

  /// Validates `FN_FORMAT`: it must be empty/unset or exactly `http-stream`.
  ///
  /// - Throws: ``FunctionRuntimeError/unsupportedFormat(_:)`` for any other value.
  public static func validateFormat(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    let format = environment["FN_FORMAT"] ?? ""
    guard format.isEmpty || format == "http-stream" else {
      throw FunctionRuntimeError.unsupportedFormat(format)
    }
  }
}
