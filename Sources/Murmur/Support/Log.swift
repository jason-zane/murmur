import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.jasonhunt.murmur", category: "audio")
    static let speech = Logger(subsystem: "com.jasonhunt.murmur", category: "speech")
    static let hotkey = Logger(subsystem: "com.jasonhunt.murmur", category: "hotkey")
    static let inject = Logger(subsystem: "com.jasonhunt.murmur", category: "inject")
    static let app = Logger(subsystem: "com.jasonhunt.murmur", category: "app")
}
