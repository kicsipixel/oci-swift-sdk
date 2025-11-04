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

/// A description of workRequest status.
public struct WorkRequest: Codable {
  /// The [OCID](https://docs.oracle.com/iaas/Content/General/Concepts/identifiers.htm) of the compartment that contains the work request. Work requests are scoped to the same compartment as the resource the work request affects.
  /// If the work request affects multiple resources and those resources are not in the same compartment, the OCID of the primary resource is used. For example, you can copy an object in a bucket in one compartment to a bucket in another compartment. In this case, the OCID of the source compartment is used.
  public let compartmentId: String?
  /// The id of the work request.
  public let id: String?
  ///
  public let operationType: OperationType?
  /// Percentage of the work request completed.
  public let percentComplete: Float?
  public let resources: [WorkRequestResource]?
  /// The status of the specified work request
  public let status: WorkRequestStatus?
  /// The raw string value of the time the work request was accepted.
  private let timeAcceptedRaw: String
  /// The raw string value of the time the work request was finished.
  private let timeFinishedRaw: String
  /// The raw string value of the time the work request was started.
  private let timeStartedRaw: String
  /// The parsed date and time the work request was accepted, based on RFC 3339 format.
  public var timeAccepted: Date? {
    Date.fromRFC3339(timeAcceptedRaw)
  }

  /// The parsed date and time the work request was finished, based on RFC 3339 format.
  public var timeFinished: Date? {
    Date.fromRFC3339(timeFinishedRaw)
  }

  /// The parsed date and time the work request was started, based on RFC 3339 format.
  public var timeStarted: Date? {
    Date.fromRFC3339(timeStartedRaw)
  }

  private enum CodingKeys: String, CodingKey {
    case compartmentId
    case id
    case operationType
    case percentComplete
    case resources
    case status
    case timeAcceptedRaw = "timeAccepted"
    case timeFinishedRaw = "timeFinished"
    case timeStartedRaw = "timeStarted"
  }
}

public enum OperationType: String, Codable {
  case copyObject = "COPY_OBJECT"
  case reencrypt = "REENCRYPT"
}

public enum WorkRequestStatus: String, Codable {
  case accepted = "ACCEPTED"
  case inProgress = "IN_PROGRESS"
  case failed = "FAILED"
  case completed = "COMPLETED"
  case canceling = "CANCELING"
  case canceled = "CANCELED"
}
