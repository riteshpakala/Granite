//  WHAT: The hop every service's helpers send through: inline on main, hopped from anywhere else, so
//        each writer's order is the main queue's.
//  PIN:  GRANITE'S `send` IS MAIN-ONLY. It stores the payload on the calling thread while the main
//        queue commits the previous send into the same slot; from another thread the two race (a
//        double release, Signal 11, seen 2026-10-05). An effect never calls `center.x.send`.

import Foundation

@inlinable
public func onMain(_ body: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
        body()
    } else {
        DispatchQueue.main.async(execute: body)
    }
}
