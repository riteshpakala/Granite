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
        if delay > .zero {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NotificationCenter.default.post(.init(name: self.asNotification))
            }
        } else {
            NotificationCenter.default.post(.init(name: self.asNotification))
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
