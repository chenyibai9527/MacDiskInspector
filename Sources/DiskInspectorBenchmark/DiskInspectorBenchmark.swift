import Darwin
import DiskInspectorCore
import Foundation

private struct Options {
    var fileCount = 10_000
    var directoryCount = 100
    var payloadBytes = 1
    var aggregationDepth = 3

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard index + 1 < arguments.count, let value = Int(arguments[index + 1]) else {
                throw BenchmarkError.invalidArgument(key)
            }
            switch key {
            case "--files":
                options.fileCount = value
            case "--directories":
                options.directoryCount = value
            case "--payload-bytes":
                options.payloadBytes = value
            case "--aggregation-depth":
                options.aggregationDepth = value
            default:
                throw BenchmarkError.invalidArgument(key)
            }
            index += 2
        }
        guard options.fileCount > 0,
              options.directoryCount > 0,
              options.payloadBytes >= 0,
              options.aggregationDepth > 0 else {
            throw BenchmarkError.invalidArgument("values must be positive")
        }
        return options
    }
}

private enum BenchmarkError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case validation(String)

    var description: String {
        switch self {
        case let .invalidArgument(value):
            "Invalid benchmark argument: \(value)"
        case let .validation(value):
            "Benchmark validation failed: \(value)"
        }
    }
}

private struct BenchmarkResult: Codable {
    let fileCount: Int
    let directoryCount: Int
    let payloadBytes: Int
    let fixtureCreationSeconds: Double
    let scanSeconds: Double
    let filesPerSecond: Double
    let peakResidentBytes: Int64
    let findingsCount: Int
    let issueCount: Int
    let allocatedBytes: Int64
    let logicalBytes: Int64
}

@main
private enum DiskInspectorBenchmark {
    static func main() async {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            let result = try await run(options)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ options: Options) async throws -> BenchmarkResult {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("MacDiskInspectorBenchmark-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let payload = Data(repeating: 0x4D, count: options.payloadBytes)
        let cacheRoot = root.appendingPathComponent(
            "Library/Caches/com.example.disk-benchmark",
            isDirectory: true
        )
        let fixtureStart = ContinuousClock.now
        for directoryIndex in 0..<options.directoryCount {
            try autoreleasepool {
                let directory = cacheRoot.appendingPathComponent(
                    "batch-\(directoryIndex)",
                    isDirectory: true
                )
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
        for fileIndex in 0..<options.fileCount {
            let created = autoreleasepool {
                let directoryIndex = fileIndex % options.directoryCount
                let fileURL = cacheRoot
                    .appendingPathComponent("batch-\(directoryIndex)", isDirectory: true)
                    .appendingPathComponent("item-\(fileIndex).bin")
                return manager.createFile(atPath: fileURL.path, contents: payload)
            }
            guard created else {
                throw BenchmarkError.validation("could not create fixture file \(fileIndex)")
            }
        }
        let fixtureSeconds = seconds(since: fixtureStart)

        let scanStart = ContinuousClock.now
        let report = try await DirectoryScanner().scan(
            rootURL: root,
            configuration: ScanConfiguration(
                aggregationDepth: options.aggregationDepth,
                progressInterval: 10_000
            )
        )
        let scanSeconds = seconds(since: scanStart)

        guard report.uniqueFiles == options.fileCount else {
            throw BenchmarkError.validation(
                "expected \(options.fileCount) files, measured \(report.uniqueFiles)"
            )
        }
        guard report.findings.count <= 5 else {
            throw BenchmarkError.validation(
                "aggregation grew unexpectedly to \(report.findings.count) findings"
            )
        }

        return BenchmarkResult(
            fileCount: options.fileCount,
            directoryCount: options.directoryCount,
            payloadBytes: options.payloadBytes,
            fixtureCreationSeconds: fixtureSeconds,
            scanSeconds: scanSeconds,
            filesPerSecond: Double(options.fileCount) / max(scanSeconds, 0.000_001),
            peakResidentBytes: peakResidentBytes(),
            findingsCount: report.findings.count,
            issueCount: report.totalIssueCount,
            allocatedBytes: report.totalAllocatedBytes,
            logicalBytes: report.totalLogicalBytes
        )
    }

    private static func seconds(
        since start: ContinuousClock.Instant
    ) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) +
            Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func peakResidentBytes() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Int64(usage.ru_maxrss)
    }
}
