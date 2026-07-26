import Testing
@testable import DiskInspectorCore

@Suite("Scan trend sampling")
struct ScanTrendSeriesTests {
    @Test("Long scans retain the beginning and latest progress")
    func longScanCoverage() {
        var series = ScanTrendSeries(maximumPointCount: 160)
        for entries in stride(from: 400, through: 70_000, by: 400) {
            series.append(
                entries: entries,
                allocatedBytes: Int64(entries) * 4_096
            )
        }

        #expect(series.points.first?.entries == 0)
        #expect(series.points.last?.entries == 70_000)
        #expect(series.points.count <= 160)
        #expect(zip(series.points, series.points.dropFirst()).allSatisfy {
            $0.entries < $1.entries
        })
    }

    @Test("Updates replace an existing progress position")
    func replacesDuplicatePosition() {
        var series = ScanTrendSeries()
        series.append(entries: 400, allocatedBytes: 1_000)
        series.append(entries: 400, allocatedBytes: 2_000)

        #expect(series.points.count == 2)
        #expect(series.points.last?.allocatedBytes == 2_000)
    }
}
