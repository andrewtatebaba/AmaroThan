//
//  Item.swift
//  AmaroThanTT
//
//  Created by Opre Roma2 on 15. 7. 2025..
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
