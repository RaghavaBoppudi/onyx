import Foundation
import OSLog

struct LogChannel: Sendable {
    private let logger: Logger

    init(_ category: String) {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.onyx.camera"
        logger = Logger(subsystem: subsystem, category: category)
    }

    func info(_ message: String)    { logger.info("\(message, privacy: .public)") }
    func warning(_ message: String) { logger.warning("\(message, privacy: .public)") }
    func error(_ message: String)   { logger.error("\(message, privacy: .public)") }
}

enum Log {
    static let capture = LogChannel("capture")
    static let lens    = LogChannel("lens")
    static let render  = LogChannel("render")
    static let library = LogChannel("library")
}
