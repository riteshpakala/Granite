//
//  GraniteNavigation.Window+Component.swift
//  
//
//  Created by Ritesh Pakala on 8/21/23.
//

import Foundation
import SwiftUI

public struct WindowComponent<Content: View>: GraniteScene {
    public struct Center: GraniteCenter {
        public struct State: GraniteState {
            public init() {}
        }
        
        @Store public var state: State
        
        public init() {}
    }
    
    @Command public var center: Center
    
    var content: (() -> Content)
    var backgroundColor: Color
    public init(backgroundColor: Color,
                @ViewBuilder content: @escaping (() -> Content)) {
        self.content = content
        self.backgroundColor = backgroundColor
    }
    
//    public func launch() {
//        GraniteNavigationWindow.backgroundColor = NSColor(backgroundColor)
//
//        GraniteNavigationWindow.shared.addWindow(id: GraniteNavigationWindow.defaultMainWindowId,
//                                                 props: .resizable(900, 600).minSize(900, 600),
//                                                 isMain: true) {
//            content()
//        }
//    }
    
    public var body: some Scene {
        WindowGroup {
            #if os(macOS)
            content()
                .task {
                    //TODO: Set main window
                    GraniteNavigationWindow.setMainWindow()
                }
            #else
            EmptyView()
            #endif
        }
    }
}

//extension WindowComponent: View {
//    public var view: some View {
//        #if os(macOS)
//        ZStack {
//            Text("Granite Window")
//        }
//        .task {
//            if let window = NSApplication.shared.windows.first {
//                window.close()
//            }
//            launch()
//            GraniteLogger.debug("DidFinishLaunching heard", .utility)
//        }
//        #else
//        EmptyView()
//        #endif
//    }
//}
