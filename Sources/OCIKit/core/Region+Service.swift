//
//  Region+Service.swift
//
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

public enum Region {
    case iad, ord, phx, sjc
    
    var urlPart: String {
        switch self {
        case .iad: "us-ashburn-1"
        case .ord: "us-chicago-1"
        case .phx: "us-phoenix-1"
        case .sjc: "us-sanjose-1"
        }
    }
}

public enum Service: String {
    case language, objectstorage, generativeai
    
    func getHost(in region: Region) -> String {
        switch self {
        case .language: "language.aiservice.\(region.urlPart).oci.oraclecloud.com"
        case .objectstorage: "objectstorage.\(region.urlPart).oci.oraclecloud.com"
        case .generativeai: "inference.generativeai.\(region.urlPart).oci.oraclecloud.com"
        }
    }
}

