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

/// The request body of ``LoggingIngestClient/putLogs(logId:details:opcRequestId:timestampOpcAgentProcessing:)``.
///
/// > Note: The service enforces no practical cap on the payload size — single
/// > requests from 1 MiB up to 1 GiB have been observed to return HTTP 200 with no
/// > silent drops. Batch sizing is therefore an ergonomics decision (retry
/// > amplification and upload latency) left to the caller, or to the swift-log
/// > backend built on top of this client; flushes in the 1–10 MiB range are sensible.
public struct PutLogsDetails: Codable, Sendable {
  /// The version of the data format being used. The only permitted value is `"1.0"`.
  public let specversion: String

  /// The log batches to ingest. Each batch has a single source, type, and subject.
  public let logEntryBatches: [LogEntryBatch]

  /// Creates the body of a `PutLogs` request.
  ///
  /// - Parameters:
  ///   - specversion: The data format version. Defaults to `"1.0"`, the only permitted value.
  ///   - logEntryBatches: The log batches to ingest.
  public init(specversion: String = "1.0", logEntryBatches: [LogEntryBatch]) {
    self.specversion = specversion
    self.logEntryBatches = logEntryBatches
  }
}
