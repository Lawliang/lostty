#if os(macOS)
import Foundation

/// What a finished program printed and how it exited.
struct ProcessResult: Equatable, Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
}

/// Runs a program to completion with a deadline, the way `TmuxClient.run`
/// does: waits on semaphores (not `waitUntilExit`, which spins the run
/// loop), reads output on background queues so a full pipe can't stall it,
/// and SIGKILLs it at the deadline. Blocking: call it off the main thread.
enum ProcessRunner {
    /// nil when the program can't start or runs past `timeout`. `onStart`
    /// gets the pid, so a caller can kill a run it no longer wants.
    static func run(
        _ executable: String,
        _ args: [String],
        cwd: String? = nil,
        environment: [String: String] = [:],
        stdin: String? = nil,
        timeout: TimeInterval,
        onStart: ((Int32) -> Void)? = nil
    ) -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        // stdin comes from a file, not a pipe: writing to a pipe whose reader
        // already exited would raise SIGPIPE in the app.
        var inputFile: URL?
        defer { if let inputFile { try? FileManager.default.removeItem(at: inputFile) } }
        if let stdin {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lostty-stdin-\(UUID().uuidString)")
            guard (try? Data(stdin.utf8).write(to: url)) != nil,
                  let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            inputFile = url
            process.standardInput = handle
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        onStart?(process.processIdentifier)

        let output = Output()
        let read = DispatchGroup()
        read.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            output.out = out.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }
        read.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            output.err = err.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }

        let deadline = DispatchTime.now() + timeout
        guard exited.wait(timeout: deadline) == .success else {
            kill(process.processIdentifier, SIGKILL)
            return nil
        }
        guard read.wait(timeout: deadline) == .success else { return nil }
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: output.out, as: UTF8.self),
            stderr: String(decoding: output.err, as: UTF8.self))
    }

    /// Hands output from the reading queues back to `run`; the group orders
    /// the writes before the reads.
    private final class Output: @unchecked Sendable {
        var out = Data()
        var err = Data()
    }
}
#endif
