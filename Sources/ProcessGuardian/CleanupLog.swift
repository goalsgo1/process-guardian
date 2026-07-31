import Foundation

/// 실행 이력. jsonl(한 줄에 항목 하나) 형식으로 저장해서, 필요하면 이 파일을 그대로
/// Claude에게 보여주고 "잘 됐는지 확인해줘" 라고 물어볼 수 있게 함.
struct CleanupLogEntry: Codable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(categoryID)" }
    let timestamp: Date
    let categoryID: String
    let categoryName: String
    let requestedBytes: Int64
    let freedBytes: Int64
    let succeededCount: Int
    let failed: [CleanupExecutor.PathError]
    let message: String

    var isSuccess: Bool { failed.isEmpty }
}

enum CleanupLogStore {
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProcessGuardian", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cleanup-log.jsonl")
    }()

    static var logFilePath: String { fileURL.path }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func append(_ entry: CleanupLogEntry) {
        guard let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write((line + "\n").data(using: .utf8)!)
    }

    /// 최신 항목이 먼저 오도록 반환
    static func loadAll() -> [CleanupLogEntry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let entries: [CleanupLogEntry] = content
            .split(separator: "\n")
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(CleanupLogEntry.self, from: data)
            }
        return entries.reversed()
    }
}
