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
import Logging

public enum PublicAccessType: String {
    case noPublicAccess = "NoPublicAccess"
    case objectRead = "ObjectRead"
    case objectReadWithoutList = "ObjectReadWithoutList"
    case unknownEnumValue = "UNKNOWN_ENUM_VALUE"
}

public enum StorageTier: String {
    case standard = "Standard"
    case archive = "Archive"
    case unknownEnumValue = "UNKNOWN_ENUM_VALUE"
}

public enum Versoning: String {
    case enabled = "Enabled"
    case suspended = "Suspended"
    case disabled = "Disabled"
    case unknownEnumValue = "UNKNOWN_ENUM_VALUE"
}

public enum AutoTiring: String {
    case disabled = "Disabled"
    case infrequentAccess = "InfrequentAccess"
    case unknownEnumValue = "UNKNOWN_ENUM_VALUE"
}
