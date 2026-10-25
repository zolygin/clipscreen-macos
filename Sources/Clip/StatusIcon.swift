import AppKit

enum StatusIcon {
    static func clipboard(paused: Bool = false) -> NSImage {
        (paused ? LucideIcon.pause : .clipboard).image(size: 18)
    }
}
