import Foundation

public enum FindingSortMode: Sendable {
    case size
    case category
    case risk
}

public struct FindingSorter: Sendable {
    public init() {}

    public func sort(_ findings: [Finding], by mode: FindingSortMode) -> [Finding] {
        findings.sorted { left, right in
            switch mode {
            case .size:
                return compareBySizeThenPath(left, right)
            case .category:
                if categoryRank(left.category) != categoryRank(right.category) {
                    return categoryRank(left.category) < categoryRank(right.category)
                }
                return compareBySizeThenPath(left, right)
            case .risk:
                if left.risk.rank != right.risk.rank {
                    return left.risk.rank > right.risk.rank
                }
                return compareBySizeThenPath(left, right)
            }
        }
    }

    private func compareBySizeThenPath(_ left: Finding, _ right: Finding) -> Bool {
        if left.allocatedBytes != right.allocatedBytes {
            return left.allocatedBytes > right.allocatedBytes
        }
        return left.path.localizedStandardCompare(right.path) == .orderedAscending
    }

    private func categoryRank(_ category: FindingCategory) -> Int {
        switch category {
        case .anomalous: 0
        case .appManaged: 1
        case .regenerableCache: 2
        case .userData: 3
        case .systemManaged: 4
        case .unknown: 5
        case .inaccessible: 6
        }
    }
}
