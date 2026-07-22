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

/// A single log record inside a ``LogEntryBatch``.
///
/// > Important: The service silently truncates any ``data`` longer than
/// > **10,000 characters** to exactly 10,000 characters ending in `...`; the
/// > request still succeeds with HTTP 200. Split long messages client-side
/// > (a little under 10,000 characters per part) if the full text matters.
///
/// Content must be valid UTF-8. When ``data`` holds JSON, the service indexes it
/// as a structured log: at most 10,000 fields, field names up to 128 bytes and
/// field values up to 10,000 bytes.
public struct LogEntry: Codable, Sendable {
  /// The log entry content.
  ///
  /// Longer than 10,000 characters is accepted but silently truncated by the service.
  public let data: String

  /// A UUID uniquely representing this log entry. This is not an OCID and is not
  /// related to any OCI resource; it only has to be unique within the request.
  public let id: String

  /// The timestamp associated with this entry, RFC3339-formatted with milliseconds
  /// precision. When `nil`, the service falls back to the batch's
  /// ``LogEntryBatch/defaultlogentrytime``.
  public let time: String?

  /// Creates a log entry.
  ///
  /// - Parameters:
  ///   - data: The log entry content. Truncated by the service beyond 10,000 characters.
  ///   - id: A UUID uniquely identifying this entry. Defaults to a freshly generated UUID.
  ///   - time: The timestamp of this entry, encoded as RFC3339 with milliseconds.
  ///     When `nil` the batch's `defaultlogentrytime` applies.
  public init(data: String, id: String = UUID().uuidString, time: Date? = nil) {
    self.data = data
    self.id = id
    self.time = time?.toRFC3339()
  }
}
