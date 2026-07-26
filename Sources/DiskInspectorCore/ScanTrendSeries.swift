import Foundation

public struct ScanTrendPoint: Identifiable, Hashable, Sendable {
    public var id: Int { entries }
    public let entries: Int
    public let allocatedBytes: Int64

    public init(entries: Int, allocatedBytes: Int64) {
        self.entries = max(0, entries)
        self.allocatedBytes = max(0, allocatedBytes)
    }
}

public struct ScanTrendSeries: Sendable {
    public private(set) var points: [ScanTrendPoint]
    public let maximumPointCount: Int

    public init(maximumPointCount: Int = 160) {
        self.maximumPointCount = max(8, maximumPointCount)
        self.points = [ScanTrendPoint(entries: 0, allocatedBytes: 0)]
    }

    public mutating func append(entries: Int, allocatedBytes: Int64) {
        let point = ScanTrendPoint(entries: entries, allocatedBytes: allocatedBytes)
        guard point.entries >= (points.last?.entries ?? 0) else { return }
        if points.last?.entries == point.entries {
            points.removeLast()
        }
        points.append(point)
        compactIfNeeded()
    }

    private mutating func compactIfNeeded() {
        guard points.count > maximumPointCount else { return }
        let latest = points.last
        points = points.enumerated().compactMap { index, point in
            index.isMultiple(of: 2) ? point : nil
        }
        if let latest, points.last?.entries != latest.entries {
            points.append(latest)
        }
    }
}
