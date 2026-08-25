//  Log.swift
//  The only file in the app that imports OSLog.
//
//  `Logger.info("...")` builds an `OSLogMessage` through a custom string
//  interpolation, so the `os` module has to be visible at every call site. Wrapping
//  the loggers behind plain-`String` functions keeps that import here instead of
//  spreading it across every file that happens to log. Same principle as keeping
//  SwiftUI's `Angle` out of Camera/: push the type outward, don't pull the import
//  inward.

import Foundation
import OSLog

struct LogChannel: Sendable {
    private let logger: Logger

    init(_ category: String) {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.onyx.camera"
        logger = Logger(subsystem: subsystem, category: category)
    }

    // `.public` because these are development diagnostics — without it Console
    // redacts every interpolated value to <private> and the log is useless.
    func debug(_ message: String)   { logger.debug("\(message, privacy: .public)") }
    func info(_ message: String)    { logger.info("\(message, privacy: .public)") }
    func warning(_ message: String) { logger.warning("\(message, privacy: .public)") }
    func error(_ message: String)   { logger.error("\(message, privacy: .public)") }
}

enum Log {
    static let session = LogChannel("session")
    static let capture = LogChannel("capture")
    static let lens    = LogChannel("lens")
    static let render  = LogChannel("render")
    static let library = LogChannel("library")
}
