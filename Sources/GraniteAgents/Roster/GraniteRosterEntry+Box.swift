import Foundation

extension GraniteRosterEntry {
    /// An entry on its way from a record to the roster: the record returns it retained, as a raw pointer a
    /// C function can carry, and discovery takes it back.
    final class Box {
        let entry: GraniteRosterEntry

        init(_ entry: GraniteRosterEntry) {
            self.entry = entry
        }

        func retained() -> UnsafeMutableRawPointer {
            Unmanaged.passRetained(self).toOpaque()
        }

        static func take(_ pointer: UnsafeMutableRawPointer) -> GraniteRosterEntry {
            Unmanaged<Box>.fromOpaque(pointer).takeRetainedValue().entry
        }
    }
}
