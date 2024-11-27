//
//  View+Frame.swift
//  
//
//  Created by Ritesh Pakala on 1/3/23.
//

import Foundation
import SwiftUI

extension View {
    public func fitToContainer(alignment: Alignment = .center) -> some View {
        return self.frame(maxWidth: .infinity,
                          maxHeight: .infinity,
                          alignment: alignment)
    }
}
