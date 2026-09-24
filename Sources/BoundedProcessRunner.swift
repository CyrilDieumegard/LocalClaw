import Darwin
import Foundation

/// Collects a launched process without letting an inherited output pipe extend
/// its deadline. The caller owns process setup and its onStart callback.
enum BoundedProcessRunner {
    struct Result {
        let exitCode: Int32
        let output: Data
        let timedOut: Bool
    }

    static func collect(_ process: Process, pipe: Pipe, timeoutSeconds: Int?) -> Result {
        let reader = pipe.fileHandleForReading
        guard let timeoutSeconds, timeoutSeconds > 0 else {
            let output = reader.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(exitCode: process.terminationStatus, output: output, timedOut: false)
        }

        let timeoutNanoseconds = UInt64(timeoutSeconds).multipliedReportingOverflow(by: 1_000_000_000)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let deadline = startedAt.addingReportingOverflow(timeoutNanoseconds.partialValue)
        let deadlineNanoseconds = timeoutNanoseconds.overflow || deadline.overflow
            ? UInt64.max : deadline.partialValue
        let descriptor = reader.fileDescriptor
        var output = Data()
        var reachedEOF = false
        var readFailed = false
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadlineNanoseconds { break }
            if reachedEOF && !process.isRunning { break }
            if reachedEOF {
                usleep(50_000)
                continue
            }

            let remainingMilliseconds = (deadlineNanoseconds - now) / 1_000_000
            let waitMilliseconds = Int32(min(100, max(1, remainingMilliseconds)))
            var event = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let ready = Darwin.poll(&event, 1, waitMilliseconds)
            if ready == 0 || (ready < 0 && errno == EINTR) { continue }
            if ready < 0 || event.revents & Int16(POLLNVAL) != 0 {
                readFailed = true
                break
            }
            if event.revents & Int16(POLLIN | POLLHUP | POLLERR) == 0 { continue }

            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                output.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                reachedEOF = true
            } else if errno != EINTR && errno != EAGAIN {
                readFailed = true
                break
            }
        }

        if !readFailed && reachedEOF && !process.isRunning,
           DispatchTime.now().uptimeNanoseconds < deadlineNanoseconds {
            process.waitUntilExit()
            return Result(exitCode: process.terminationStatus, output: output, timedOut: false)
        }

        // A descendant can retain the pipe after the direct child exits. Do
        // not wait for that descendant's EOF, and never kill an unowned group.
        try? reader.close()
        stopDirectChild(process)
        return Result(exitCode: 124, output: output, timedOut: true)
    }

    private static func stopDirectChild(_ process: Process) {
        if process.isRunning { process.terminate() }
        let graceDeadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while process.isRunning && DispatchTime.now().uptimeNanoseconds < graceDeadline {
            usleep(50_000)
        }
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}
