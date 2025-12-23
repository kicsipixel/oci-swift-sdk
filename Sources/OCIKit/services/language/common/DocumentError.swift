//
//  DocumentError.swift
//
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

struct DocumentError: Codable {
  let error: ErrorDetails
  let key: String
}

struct ErrorDetails: Codable {
  let code: String
  let message: String
}
