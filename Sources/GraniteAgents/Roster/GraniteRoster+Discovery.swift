import Foundation
#if canImport(MachO)
import MachO
#endif

extension GraniteRoster {
    /// Where a package places its record.
    public static let segment = "__DATA_CONST"
    public static let section = "__granite"

    /// Every record in every image this process has loaded, each called once: the package agents and
    /// worker specs of the packages the app links, with nothing listed by hand. Walks the images each
    /// time it is called; an app keeps the roster it found.
    public static func discovered() -> GraniteRoster {
        #if canImport(MachO)
        var entries: [GraniteRosterEntry] = []
        let stride = MemoryLayout<Record>.stride
        for image in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(image) else { continue }
            var size: UInt = 0
            let start = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
                getsectiondata($0, segment, section, &size)
            }
            guard let start, size > 0 else { continue }
            let records = UnsafeRawPointer(start)
            for index in 0..<(Int(size) / stride) {
                let record = records.load(fromByteOffset: index * stride, as: Record.self)
                if let made = record() { entries.append(GraniteRosterEntry.Box.take(made)) }
            }
        }
        return GraniteRoster(entries)
        #else
        return .empty
        #endif
    }
}
