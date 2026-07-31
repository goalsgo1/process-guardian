import Foundation

enum DiskLevel {
    case green, yellow, red
}

struct DiskStatus {
    let usedPercent: Int
    let freeBytes: Int64
    let totalBytes: Int64

    var level: DiskLevel {
        if usedPercent >= 90 { return .red }
        if usedPercent >= 80 { return .yellow }
        return .green
    }
}

enum DiskMonitor {
    /// 실제 사용자 데이터가 쌓이는 볼륨. "/"는 시스템 전용 읽기전용 볼륨이라 여기서는 의미 없음.
    private static let targetPath = "/System/Volumes/Data"

    static func currentStatus() -> DiskStatus? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: targetPath),
              let total = attrs[.systemSize] as? NSNumber,
              let free = attrs[.systemFreeSize] as? NSNumber else {
            return nil
        }
        let totalBytes = total.int64Value
        let freeBytes = free.int64Value
        guard totalBytes > 0 else { return nil }
        let usedBytes = totalBytes - freeBytes
        let usedPercent = Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())
        return DiskStatus(usedPercent: usedPercent, freeBytes: freeBytes, totalBytes: totalBytes)
    }
}
