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

public struct WorkRequestResource: Codable {
  /// The status of the work request.
  public let actionType: ActionType?
  /// The resource type the work request affects.
  public let entityType: String?
  /// The URI path that you can use for a GET request to access the resource metadata.
  public let entityUri: String?
  /// The resource type identifier.
  public let identifier: String?
  /// The metadata of the resource.
  public let metadata: [String: String]?
}

public enum ActionType: String, Codable {
  case created = "CREATED"
  case updated = "UPDATED"
  case deleted = "DELETED"
  case related = "RELATED"
  case inProgress = "IN_PROGRESS"
  case read = "READ"
  case written = "WRITTEN"
}
