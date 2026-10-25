import os

/// The app's loggers, a category per area.
nonisolated enum Log {
    private static let subsystem = "com.pbordjadze.reader"

    static let library = Logger(subsystem: subsystem, category: "library")
    #if DEBUG
    static let demo = Logger(subsystem: subsystem, category: "demo")
    #endif
}
