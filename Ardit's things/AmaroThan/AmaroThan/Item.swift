//
//  Item.swift
//  AmaroThan
//
//  Created by Opre Roma2 on 4. 7. 2025..
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
