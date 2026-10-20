import Foundation
#if os(macOS)
import os
#endif

/// Unified logging for `log stream --predicate 'subsystem == "com.sonoslocal.mac"'`.
public enum SonosLog {
    public static let subsystem = "com.sonoslocal.mac"

    public static func discovery(_ message: String) {
        write("discovery", message)
    }

    public static func network(_ message: String) {
        write("network", message)
    }

    private static func write(_ category: String, _ message: String) {
        #if os(macOS)
        Logger(subsystem: subsystem, category: category).info("\(message, privacy: .public)")
        #endif
    }
}
