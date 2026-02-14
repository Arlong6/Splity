//
//  Item.swift
//  Splity
//
//  Created by 簡川隆 on 2026/2/15.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
