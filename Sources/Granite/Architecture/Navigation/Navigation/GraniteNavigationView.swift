//
//  GraniteNavigationView.swift
//  
//
//  Created by Ritesh Pakala on 8/21/23.
//

import Foundation
import SwiftUI

//MARK: GraniteNavigationView
struct GraniteNavigationView<Content: View>: View {
    @Environment(\.graniteNavigationStyle) var style
    
    @ObservedObject var routes: GraniteNavigation
    
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) {
        
        if GraniteNavigation.mainSet {
            _routes = .init(initialValue: .init(isMain: false))
        } else {
            _routes = .init(initialValue: .main)
        }
        
        self.content = content
        
        GraniteLog("Navigation initializing with \(routes.id)", level: .debug)
    }
    
    var body: some View {
//        #if os(iOS)
//        NavigationView {
//            mainView
//        }
//        #else
//        mainView
//        #endif
        mainView
            .environment(\.graniteRouter, routes.asRouter)
    }
    var mainView: some View {
        ZStack(alignment: .top) {
            
            style.backgroundColor
                .ignoresSafeArea()
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity)
            
            content()
                .background(style.backgroundColor)
                .navStack()
                .onDisappear {
                    GraniteLog("releasing: \(routes.id)", level: .debug)
                    routes.releaseStack()
                }
            
            GraniteRouter()
                .environmentObject(routes)
        }
        .navBarTitle()
        .navBarHidden()
    }
}

fileprivate extension View {
    func navBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitle("", displayMode: .inline)
        #else
        self
        #endif
    }
    
    func navBarHidden() -> some View {
        #if os(iOS)
        self.navigationBarHidden(true)
        #else
        self
        #endif
    }
    
    func navStack() -> some View {
        #if os(iOS)
        self.navigationViewStyle(.stack)
        #else
        self
        #endif
    }
}
