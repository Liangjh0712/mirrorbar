import Foundation

struct ShellResult {
    let status: Int32
    let data: Data
    var output: String { String(decoding: data, as: UTF8.self) }
    var ok: Bool { status == 0 }
}

enum Shell {
    /// Run a command off the main thread and collect stdout + stderr.
    /// `includeStderr: false` keeps binary stdout (e.g. a PNG) clean of warnings.
    static func run(_ executable: String, _ arguments: [String],
                    timeout: TimeInterval = 10, includeStderr: Bool = true) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: runSync(executable, arguments, timeout: timeout,
                                                       includeStderr: includeStderr))
            }
        }
    }

    /// Blocking variant, used when the app is quitting.
    static func runSync(_ executable: String, _ arguments: [String],
                        timeout: TimeInterval = 10, includeStderr: Bool = true) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = includeStderr ? pipe : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, data: Data(error.localizedDescription.utf8))
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return ShellResult(status: process.terminationStatus, data: data)
    }
}

/// Plain-text log at ~/Library/Logs/Mirrorbar/mirrorbar.log.
enum Log {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Mirrorbar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mirrorbar.log")
    }()

    private static let queue = DispatchQueue(label: "mirrorbar.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }
}
