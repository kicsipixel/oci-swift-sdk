//===----------------------------------------------------------------------===//
//
// This source file is part of the oci-swift-sdk open source project
//
// Copyright (c) 2025 Szabolcs Toth and the oci-swift-sdk project authors
// Licensed under MIT License
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of oci-swift-sdk project authors
//
// SPDX-License-Identifier: MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

/// NamespaceMetadata maps a namespace string to defaultS3CompartmentId and defaultSwiftCompartmentId values.
public struct NamespaceMetadata: Codable {
  /// If the field is set, specifies the default compartment assignment for the Amazon S3 Compatibility API.
  public let defaultS3CompartmentId: String
  /// If the field is set, specifies the default compartment assignment for the Swift API.
  public let defaultSwiftCompartmentId: String
  /// The Object Storage namespace to which the metadata belongs.
  public let namespace: String
}
