import Foundation

public struct VolumeReader: Sendable {
    public init() {}

    public func capacity(for url: URL) throws -> VolumeCapacity {
        let resourceKeys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        let values = try url.resourceValues(forKeys: resourceKeys)
        return VolumeCapacity(
            name: values.volumeName ?? url.lastPathComponent,
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: Int64(values.volumeAvailableCapacity ?? 0),
            availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage
        )
    }
}
