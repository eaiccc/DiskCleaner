//
//  Item.swift
//  DiskCleaner
//
//  Created by Link on 2026/6/3.
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
