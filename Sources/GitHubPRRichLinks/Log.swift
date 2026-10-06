import Foundation

public enum Log {
    nonisolated(unsafe) public static var verbose = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func info(_ message: String) {
        write(message)
    }

    public static func debug(_ message: String) {
        guard verbose else { return }
        write(message)
    }

    public static func error(_ message: String) {
        write("error: \(message)")
    }

    private static func write(_ message: String) {
        FileHandle.standardError.write("\(formatter.string(from: Date())) \(message)\n".data(using: .utf8)!)
    }
}
