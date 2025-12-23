//
//  RelationEntity.swift
//
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

struct RelationEntity: Codable {
  let id: String
  let objectId: String
  let score: Double
  let subjectId: String
  let type: String
}
