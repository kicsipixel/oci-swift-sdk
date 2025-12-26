//
//  ResolvedEntity.swift
//
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

struct ResolvedEntities: Codable {
  let details: [ResolvedEntity]?
}

struct ResolvedEntity: Codable {
  let id: String
  let length: Int
  let offset: Int
  let text: String
  let type: String
  let value: [String: String]
}
