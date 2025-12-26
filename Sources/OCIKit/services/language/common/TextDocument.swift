//
//  TextDocument.swift
//
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

public struct TextDocument: Codable {
  let key: String
  let languageCode: String?
  let text: String

  public init(key: String, languageCode: String?, text: String) {
    self.key = key
    self.languageCode = languageCode
    self.text = text
  }
}
