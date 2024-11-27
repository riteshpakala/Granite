//
//  View+Keyboard.swift
//  
//
//  Created by Ritesh Pakala on 1/25/23.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
extension View {
  public func hideKeyboard() {
      UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}
#endif
