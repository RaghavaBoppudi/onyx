import Foundation
import OSLog

nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.onyx.camera"

    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let lens    = Logger(subsystem: subsystem, category: "lens")
    static let render  = Logger(subsystem: subsystem, category: "render")
    static let library = Logger(subsystem: subsystem, category: "library")
}
