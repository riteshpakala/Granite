//
//  Extensions.swift
//  Granite
//
//  Created by Ritesh Pakala Rao on 7/26/26.
//

import Foundation

public extension Int {
    /// A random value in `self..<secondNum`.
    ///
    /// Returns `self` when the range would be empty or invalid rather than
    /// trapping the way `Int.random(in:)` does on a reversed/empty range.
    func randomBetween(_ secondNum: Int) -> Int {
        guard secondNum > self else { return self }
        return Int.random(in: self..<secondNum)
    }
}
