import Darwin
import Foundation

public struct ScanimageResult: Sendable {
    public let output: Data
    public let diagnostic: String
    public let exitCode: Int32

    public init(output: Data, diagnostic: String = "", exitCode: Int32 = 0) {
        self.output = output
        self.diagnostic = diagnostic
        self.exitCode = exitCode
    }
}

public protocol ScanimageRunning: Sendable {
    func run(
        executable: URL, arguments: [String], timeout: TimeInterval,
        onDiagnostic: @escaping @Sendable (Data) -> Void
    ) async throws -> ScanimageResult
}

/// Runs one child directly (never via a shell), draining both pipes concurrently.
public struct ScanimageProcess: ScanimageRunning {
    public init() {}

    public func run(
        executable: URL, arguments: [String], timeout: TimeInterval,
        onDiagnostic: @escaping @Sendable (Data) -> Void
    ) async throws -> ScanimageResult {
        let control = ChildControl()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .userInitiated) {
                try control.run(executable: executable, arguments: arguments,
                                timeout: timeout, onDiagnostic: onDiagnostic)
            }.value
        } onCancel: {
            control.stop()
        }
    }
}

/// Access to the process lifecycle is serialized, including launch/cancel races.
private final class ChildControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var timedOut = false

    func stop(timeout: Bool = false) {
        lock.withLock {
            guard !stopped else { return }
            stopped = true
            timedOut = timeout
            guard let process, process.isRunning else { return }
            process.interrupt() // Let SANE cancel acquisition and release the USB device.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    func run(
        executable: URL, arguments: [String], timeout: TimeInterval,
        onDiagnostic: @escaping @Sendable (Data) -> Void
    ) throws -> ScanimageResult {
        let child = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = outputPipe
        child.standardError = errorPipe

        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            process = child
            try child.run()
        }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        defer {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        let deadline = DispatchWorkItem { [weak self] in self?.stop(timeout: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }

        let diagnostics = DiagnosticBuffer()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async {
            defer { readers.leave() }
            // A length-filling FileHandle read can hold small progress messages until EOF.
            // One POSIX pipe read returns as soon as any bytes are available.
            while let bytes = try? readAvailableChunk(errorPipe.fileHandleForReading), !bytes.isEmpty {
                diagnostics.append(bytes)
                onDiagnostic(bytes)
            }
        }

        var output = Data()
        var readError: (any Error)?
        do {
            while let bytes = try outputPipe.fileHandleForReading.read(upToCount: 65_536), !bytes.isEmpty {
                guard output.count + bytes.count <= 128 * 1_024 * 1_024 else {
                    throw ScanimageError.outputTooLarge
                }
                output.append(bytes)
            }
        } catch {
            readError = error
            stop()
        }
        child.waitUntilExit()
        readers.wait()

        let status = lock.withLock { (stopped, timedOut) }
        if let readError { throw readError }
        if status.1 { throw ScanimageError.timedOut }
        if status.0 { throw CancellationError() }
        return ScanimageResult(output: output, diagnostic: diagnostics.text, exitCode: child.terminationStatus)
    }
}

private func readAvailableChunk(_ handle: FileHandle) throws -> Data? {
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
        let count = buffer.withUnsafeMutableBytes {
            Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
        }
        if count > 0 { return Data(buffer.prefix(count)) }
        if count == 0 { return nil }
        if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

private final class DiagnosticBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ bytes: Data) {
        lock.withLock {
            data.append(bytes)
            if data.count > 16_384 { data = Data(data.suffix(16_384)) }
        }
    }

    var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}
