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

/// How the Monitoring service treats a batch of metric objects that partially fails validation.
///
/// The service name for this type is `BatchAtomicity`; it is prefixed here because OCIKit ships
/// as a single module.
public enum MonitoringBatchAtomicity: String, Codable, Sendable {
  /// The entire batch is rejected if any metric object in it fails input validation.
  case atomic = "ATOMIC"
  /// Valid metric objects are ingested and invalid ones are reported individually in
  /// ``PostMetricDataResponseDetails/failedMetrics``. This is the service default.
  case nonAtomic = "NON_ATOMIC"
}
