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

public struct BulkDeleteResourcesDetails: Codable {
  /// The resources to be deleted.
  let resources: [BulkActionResource]

  public init(resources: [BulkActionResource]) {
    self.resources = resources
  }
}
