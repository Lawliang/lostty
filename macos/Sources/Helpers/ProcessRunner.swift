#if os(macOS)
import Foundation
import OSLog

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
///
/// The readers run on private serial queues, never `DispatchQueue.global`:
/// callers may block Swift concurrency's cooperative threads (one per CPU),
/// and while those are all blocked the system won't give global-queue work
/// a thread, so the readers would never run and every call would time out.
/// Private serial queues are overcommit and always get a thread.
enum ProcessRunner {
    private static let logger = Logger(subsystem: "com.lawliang.lostty", category: "process")

    /// nil when the program can't start or runs past `timeout`. `onStart`
    /// gets the pid, so a caller can kill a run it no longer wants.
    /// `environment` is added to Lostty's own, or with `inheritEnvironment`
    /// false is all the program gets.
    static func run(
        _ executable: String,
        _ args: [String],
        cwd: String? = nil,
        environment: [String: String] = [:],
        inheritEnvironment: Bool = true,
        stdin: String? = nil,
        timeout: TimeInterval,
        onStart: ((Int32) -> Void)? = nil
    ) -> ProcessResult? {
        // Its own autorelease pool: Foundation autoreleases the pipes' file
        // handles, which close only when a pool drains, and a caller on a
        // thread that never returns to its pool would leak them.
        autoreleasepool {
            launch(executable, args, cwd: cwd, environment: environment, inheritEnvironment: inheritEnvironment,
                   stdin: stdin, timeout: timeout, onStart: onStart)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func launch(
        _ executable: String, _ args: [String], cwd: String?, environment: [String: String],
        inheritEnvironment: Bool, stdin: String?, timeout: TimeInterval, onStart: ((Int32) -> Void)?
    ) -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if !inheritEnvironment {
            process.environment = environment
        } else if !environment.isEmpty {
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
            logger.error("couldn't start \(executable, privacy: .public): \(error, privacy: .public)")
            return nil
        }
        onStart?(process.processIdentifier)

        let output = Output()
        let read = DispatchGroup()
        read.enter()
        DispatchQueue(label: "lostty.process-runner.read", qos: .userInitiated).async {
            output.out = out.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }
        read.enter()
        DispatchQueue(label: "lostty.process-runner.read", qos: .userInitiated).async {
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
