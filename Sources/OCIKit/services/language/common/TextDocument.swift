//
//  TextDocument.swift
//  
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

struct TextDocument: Codable {
    let key: String
    let languageCode: String?
    let text: String
}
