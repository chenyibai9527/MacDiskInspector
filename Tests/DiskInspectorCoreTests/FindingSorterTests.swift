import Testing
@testable import DiskInspectorCore

@Suite("Finding sorting")
struct FindingSorterTests {
    private let sorter = FindingSorter()

    @Test("Size sorting is descending and deterministic")
    func sizeSorting() {
        let findings = [
            finding(path: "/b", size: 100, category: .unknown, risk: .medium),
            finding(path: "/c", size: 300, category: .unknown, risk: .medium),
            finding(path: "/a", size: 100, category: .unknown, risk: .medium)
        ]

        #expect(sorter.sort(findings, by: .size).map(\.path) == ["/c", "/a", "/b"])
    }

    @Test("Category sorting groups types and keeps size order")
    func categorySorting() {
        let findings = [
            finding(path: "/unknown", size: 900, category: .unknown, risk: .medium),
            finding(path: "/cache-small", size: 100, category: .regenerableCache, risk: .low),
            finding(path: "/anomaly", size: 50, category: .anomalous, risk: .medium),
            finding(path: "/cache-large", size: 500, category: .regenerableCache, risk: .low)
        ]

        #expect(
            sorter.sort(findings, by: .category).map(\.path) ==
            ["/anomaly", "/cache-large", "/cache-small", "/unknown"]
        )
    }

    @Test("Risk sorting puts protected and high-risk data first")
    func riskSorting() {
        let findings = [
            finding(path: "/low", size: 900, category: .regenerableCache, risk: .low),
            finding(path: "/medium", size: 800, category: .unknown, risk: .medium),
            finding(path: "/medium-larger", size: 1_000, category: .regenerableCache, risk: .medium),
            finding(path: "/protected", size: 100, category: .systemManaged, risk: .prohibited),
            finding(path: "/high", size: 200, category: .userData, risk: .high)
        ]

        #expect(
            sorter.sort(findings, by: .risk).map(\.path) ==
            ["/protected", "/high", "/medium-larger", "/medium", "/low"]
        )
    }

    private func finding(
        path: String,
        size: Int64,
        category: FindingCategory,
        risk: FindingRisk
    ) -> Finding {
        Finding(
            path: path,
            allocatedBytes: size,
            logicalBytes: size,
            fileCount: 1,
            lastModified: nil,
            sourceApplication: nil,
            category: category,
            risk: risk,
            confidence: .high,
            explanation: "",
            potentialReclaimableBytes: nil,
            reclaimability: .notEstimated,
            recommendedAction: "",
            ruleIdentifier: "test"
        )
    }
}
