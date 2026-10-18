//
//  Prospect+Environment.swift
//  Granite
//
//  Carries the enclosing scope down the SwiftUI view tree, so a component's command joins
//  its parent component's (or pushed screen's) scope — the view hierarchy is the chain.
//

import SwiftUI

private struct GraniteProspectKey: EnvironmentKey {
    static let defaultValue: Prospect? = nil
}

extension EnvironmentValues {
    /// The scope that commands built beneath this point attach to.
    public var graniteProspect: Prospect? {
        get { self[GraniteProspectKey.self] }
        set { self[GraniteProspectKey.self] = newValue }
    }
}
