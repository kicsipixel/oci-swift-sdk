//
//  Profile.swift
//
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

public struct Profile: Codable {
    let documentType: String?
    let domain: String?
    let specialty: String?
  
  public init(documentType: String?, domain: String?, specialty: String?) {
    self.documentType = documentType
    self.domain = domain
    self.specialty = specialty
  }
}
