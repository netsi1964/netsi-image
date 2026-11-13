import Foundation

public enum PathConfinementError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyRelativePath
    case absolutePath(String)
    case escapesRoot(String)

    public var description: String {
        switch self {
        case .emptyRelativePath:
            return "Stien er tom."
        case .absolutePath(let path):
            return "Stien må ikke være absolut: \(path)"
        case .escapesRoot(let path):
            return "Stien ligger uden for biblioteket: \(path)"
        }
    }
}

/// Every write in the library goes through these checks before a byte is written.
public enum PathConfinement {
    /// Resolve a relative path under a root, rejecting absolute paths, `..`, `~`
    /// and any result that escapes the root once symlinks are resolved.
    public static func resolve(relative path: String, under root: URL) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PathConfinementError.emptyRelativePath }
        guard !trimmed.hasPrefix("/") && !trimmed.hasPrefix("~") else {
            throw PathConfinementError.absolutePath(path)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { throw PathConfinementError.emptyRelativePath }
        guard !components.contains("..") else { throw PathConfinementError.escapesRoot(path) }

        let candidate = components.reduce(root) { $0.appendingPathComponent($1) }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(resolvedCandidate, root: resolvedRoot) else {
            throw PathConfinementError.escapesRoot(path)
        }
        return candidate
    }

    public static func contains(_ candidate: URL, root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidateComponents = candidate.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    public static func ensureContained(_ candidate: URL, root: URL) throws {
        guard contains(candidate, root: root) else {
            throw PathConfinementError.escapesRoot(candidate.path)
        }
    }
}

public protocol FileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

/// Temp file in the destination directory, then rename. A crash never leaves a half-written image.
public struct AtomicFileWriter: FileWriting {
    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporary, to: url)
    }
}

/// A writer that fails on a chosen call, used to prove atomicity.
public struct FailingFileWriter: FileWriting {
    public let failingCall: Int
    private let counter = Counter()

    public init(failOn call: Int) {
        self.failingCall = call
    }

    public func write(_ data: Data, to url: URL) throws {
        let call = counter.next()
        if call >= failingCall {
            throw CocoaError(.fileWriteUnknown)
        }
        try AtomicFileWriter().write(data, to: url)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
