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
#if canImport(Observation)
import Observation
#endif

public class ListObjects: Codable  {
  /// The name of the object to use in the start parameter to obtain the next page of a truncated ListObjects response. Avoid entering confidential information. Example: test/object1.log
  public var nextStartWith: String?
  /// An array of object summaries.
  public var objects: [ObjectSummary]
  /// Prefixes that are common to the results returned by the request if the request specified a delimiter.
  public var prefixes: [String]?
    
    public init(nextStartWith: String?, objects: [ObjectSummary], prefixes: [String]?) {
        self.nextStartWith = nextStartWith
        self.objects = objects
        self.prefixes = prefixes
    }
}
