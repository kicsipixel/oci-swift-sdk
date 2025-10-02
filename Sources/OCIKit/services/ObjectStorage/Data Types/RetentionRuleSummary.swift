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

public struct RetentionRuleSummary: Codable {
    /// User specified name for the retention rule.
    public let displayName: String
    public let duration: Duration?
    /// The entity tag (ETag) for the retention rule.
    public let etag: String
    /// Unique identifier for the retention rule.
    public let id: String
    /// The date and time that the retention rule was created as per RFC3339.
    public let timeCreated: String
    /// The date and time that the retention rule was modified as per RFC3339.
    public let timeModified: String
    /// The date and time as per RFC 3339 after which this rule becomes locked. and can only be deleted by deleting the bucket.
    public let timeRuleLocked: String?
}
