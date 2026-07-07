//
//  Granite.swift
//  
//
//  Created by Ritesh Pakala on 8/21/23.
//

import Foundation

public protocol AnyGraniteNotification {
    
}

extension AnyGraniteNotification where Self: RawRepresentable, Self.RawValue == String {
    public var asNotification: Notification.Name {
        .init(self.rawValue)
    }
    
    public var publisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: self.asNotification)
    }
    
    public func post(delay: Double = .zero) {
        // Capture the Sendable Notification.Name rather than `self` so the deferred closure
        // doesn't send a potentially non-Sendable `Self` across the main-queue boundary.
        let name = self.asNotification
        if delay > .zero {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NotificationCenter.default.post(.init(name: name))
            }
        } else {
            NotificationCenter.default.post(.init(name: name))
        }
    }
}

public struct Granite {
    public struct App {
        public enum Lifecycle: String, AnyGraniteNotification {
            case didFinishLaunching = "nyc.stoic.Granite.App.Lifecycle.DidFinishLaunching"
        }
        
        public enum Interaction: String, AnyGraniteNotification {
            case windowClickedOutside = "nyc.stoic.Granite.App.Interaction.windowClickedOutside"
            case windowClickedInside = "nyc.stoic.Granite.App.Interaction.windowClickedInside"
        }
    }
}
