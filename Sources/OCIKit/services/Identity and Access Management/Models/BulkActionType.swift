//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Szabolcs Tóth and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

/// Represents the type of bulk action that can be performed on compartment resources.
///
/// Allowed values:
/// - `bulkMoveResources`
/// - `bulkDeleteResources`
public enum BulkActionType: String {
  /// Move multiple resources to a different compartment.
  case bulkMoveResources = "BULK_MOVE_RESOURCES"

  /// Delete multiple resources within a compartment.
  case bulkDeleteResources = "BULK_DELETE_RESOURCES"
}
