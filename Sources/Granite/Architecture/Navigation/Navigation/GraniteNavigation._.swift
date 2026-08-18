//
//  GraniteNavigation.swift
//
//
//  Created by Ritesh Pakala on 2/26/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI


//MARK: GraniteNavigation
//Main stack
@MainActor
public final class GraniteNavigation: ObservableObject {
    
    // `Router` is a lightweight, Sendable value (it stores only a String id). Its *actions*
    // touch main-actor navigation state, so those are `@MainActor`; the value itself is
    // nonisolated so it can be constructed as an EnvironmentKey default.
    public struct Router: Sendable {
        public let id: String
        public init(id: String) {
            self.id = id
        }

        @MainActor
        public var navigation: GraniteNavigation {
            GraniteNavigation.instance(for: id)
        }

        @MainActor
        public func push<C: View>(style: GraniteNavigationDestinationStyle = .init(),
                                  window: GraniteRouteWindowProperties? = nil,
                                  @ViewBuilder _ content: @escaping () -> C) {
            self.navigation.push(destinationStyle: style,
                                 window: window,
                                 content)
        }

        @MainActor
        public func push<C: GraniteNavigationDestination>(window: GraniteRouteWindowProperties? = nil,
                                                          @ViewBuilder _ content: @escaping () -> C) {
            self.navigation.push(window: window,
                                 content)
        }

        @MainActor
        public func pop() {
            self.navigation.pop()
        }
    }
    public var asRouter: Router {
        .init(id: self.id)
    }

    func addressHeap<T: AnyObject>(o: T) -> Int {
        return unsafeBitCast(o, to: Int.self)
    }
    
    public static var initialValue: GraniteNavigation {
        GraniteNavigation.main
    }
    
    var id: String
    
    public static func instance(for key: String) -> GraniteNavigation {
        //TODO: Wont work on tablet
        .main.child(key) ?? .main
    }
    
    public static func router(for key: String) -> Router {
        instance(for: key).asRouter
    }
    
    // App-wide navigation is main-thread UI state. It isn't internally synchronized, so the
    // shared statics are exposed as `nonisolated(unsafe)` under strict concurrency.
    nonisolated(unsafe) static var mainSet: Bool = false
    nonisolated(unsafe) public static var main: GraniteNavigation = .init(isMain: true)
    private var children: [String : GraniteNavigation] = [:]
    
    var stackCount: Int {
        children.count
    }
    
    internal var isActive = [String : Bool]()
    
    let isMain: Bool
    // `nonisolated` so the `main` static (a nonisolated global) can construct it. The main
    // instance takes a branch that touches no other instance's isolated state; child
    // instances are only ever created on the main actor (via `route`/`instance`), so the
    // main-actor accesses are bridged with a synchronous `assumeIsolated`.
    nonisolated public init(isMain: Bool) {
        if isMain {
            self.id = "granite.app.main.router"
            self.isMain = true
            GraniteNavigation.mainSet = true
        } else {
            self.isMain = false
            self.id = MainActor.assumeIsolated {
                "granite.app.main.router.child_\(GraniteNavigation.main.stackCount)"
            }
            let created = self
            MainActor.assumeIsolated {
                GraniteNavigation.main.addChild(created.id, navigation: created)
            }
        }
    }
    
    var paths: [String: () -> AnyView] = [:]
    var stack: [String] = []
    var prospectors: [String: UUID] = [:]
    
    var level: Int {
        stack.count
    }
    
    func addChild(_ key: String, navigation: GraniteNavigation) {
        GraniteLog("adding child \(key) to \(self.id)", level: .debug)
        children[key] = navigation
    }
    
    @discardableResult
    func removeChild(_ key: String) -> GraniteNavigation? {
        let navigation = children[key]
        children[key] = nil
        return navigation
    }
    
    func child(_ key: String) -> GraniteNavigation? {
        return children[key]
    }
    
    //TODO: remove GranitePayload requirement
    @discardableResult
    func set<Component : GraniteComponent>(destinationStyle: GraniteNavigationDestinationStyle = .init(),
                                           @ViewBuilder _ component: @escaping (() -> Component)) -> String {
        
        let screen = NavigationPassthroughComponent<Component, EmptyGranitePayload>.Screen<Component, EmptyGranitePayload>.init(component)
        let addr = NSString(format: "%p", addressHeap(o: screen)) as String
        
        let id: UUID = .init()
        prospectors[addr] = id
        
        paths[addr] = { AnyView(NavigationPassthroughComponent<Component,
                                EmptyGranitePayload>(screen: screen)
            .environment(\.graniteNavigationDestinationStyle, destinationStyle)) }
        
        isActive[addr] = false
        return addr
    }
    
    func push(_ addr: String,
              window: GraniteRouteWindowProperties? = nil) {
        
        GraniteLog("nav stack pushing into: \(self.id)")
        
        if let id = prospectors[addr] {
            Prospector
                .shared
                .currentNode?
                .addChild(id: id,
                          label: self.id + " | " + "pushed view",
                          type: .navigation)
            Prospector.shared.push(id: id, .navigation)
            GraniteLog("Pushed addr: \(addr) for id: \(id)", level: .debug)
        }
        
        #if os(macOS)
        if let window {
            if let path = paths[addr] {
                GraniteNavigationWindow
                    .shared
                    .addWindow(props: window) {
                        path()
                            .environment(\.graniteNavigationWindowDestinationStyle, .newWindow)
                            .graniteNavigation(backgroundColor: Color.clear)
                            .frame(minWidth: window.style.minSize.width,
                                   minHeight: window.style.minSize.height)
                    }
                
                isActive[addr] = nil
                paths[addr] = nil
            }
        } else {
            isActive[addr] = true
            stack.append(addr)
            self.objectWillChange.send()
        }
        #else
        isActive[addr] = true
        stack.append(addr)
        self.objectWillChange.send()
        #endif
    }
    
    func pop() {
        guard let addr = stack.last else { return }
        isActive[addr] = false
        stack.removeLast()
        
        #if os(iOS) || os(visionOS)
        self.objectWillChange.send()
        #endif
        
        if let id = prospectors[addr] {
            Prospector.shared.remove(id: id)
            GraniteLog("Popped addr: \(addr) for id: \(id) | node count: \(Prospector.shared.nodeCount)", level: .debug)
            
            
        }
    }
    
    func releaseStack() {
        guard self.isMain == false else { return }
        DispatchQueue.main.async { [weak self] in
            self?.stack.removeAll()
            self?.paths.removeAll()
            self?.isActive.removeAll()
            
            if let id = self?.id {
                GraniteNavigation.main.removeChild(id)
                GraniteLog("Navigation Stack Released", level: .debug)
            }
        }
    }
}

extension View {
    public func graniteNavigation(backgroundColor: Color = .black,
                                  disable: Bool = false) -> some View {
        
        self.initUINavigation(backgroundColor)
        
        return self.initNavigationView(disable: disable,
                                       style: .init(backgroundColor: backgroundColor))
    }
    
    public func graniteNavigation(backgroundColor: Color = .black,
                                  disable: Bool = false,
                                  @ViewBuilder leadingItem: @escaping () -> some View) -> some View {
        
        self.initUINavigation(backgroundColor)
        
        return self.initNavigationView(disable: disable,
                                       style: .init(leadingButtonKind: .customView,
                                                    backgroundColor: backgroundColor,
                                                    leadingItem: leadingItem))
    }
    
    private func initUINavigation(_ backgroundColor: Color) {
        #if os(iOS) || os(visionOS)
        //        UINavigationBar.appearance().isUserInteractionEnabled = false
        UINavigationBar.appearance().backgroundColor = UIColor(backgroundColor)
        //        UINavigationBar.appearance().barTintColor = .clear
        //        UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
        UINavigationBar.appearance().shadowImage = UIImage()
        //        UINavigationBar.appearance().tintColor = .clear
        //        UINavigationBar.appearance().isOpaque = true
        
        if #available(iOS 15, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.backgroundColor = UIColor(backgroundColor)
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        #endif
    }
    
    private func initNavigationView(disable: Bool,
                                    disableiOS16: Bool = true,
                                    style: GraniteNavigationStyle) -> some View {
        Group {
            if disable {
                self
                    .environment(\.graniteNavigationStyle, style)
            } else {
                if !disableiOS16,
                   #available(macOS 13.0, iOS 16.0, *) {
                    NavigationStack {//WIP
                        ZStack(alignment: .top) {
                            style.backgroundColor
                                .ignoresSafeArea()
                                .frame(maxWidth: .infinity,
                                       maxHeight: .infinity)
                            self
                                .background(style.backgroundColor)
                        }
                    }
                    .environment(\.graniteNavigationStyle, style)
                } else {
                    GraniteNavigationView {
                        self
                    }
                    .environment(\.graniteNavigationStyle, style)
                }
            }
        }
    }
}
