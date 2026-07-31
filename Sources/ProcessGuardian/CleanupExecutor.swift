import Foundation

enum CleanupExecutor {
    struct PathError: Codable {
        let path: String
        let error: String
    }

    struct Result {
        let categoryName: String
        let freedBytes: Int64
        let succeededCount: Int
        let failed: [PathError]
        let message: String

        var isSuccess: Bool { failed.isEmpty }
    }

    /// 실행 직전 재검사 후 삭제한다 (스캔 시점과 실행 시점 사이 상태 변화 대응).
    /// 모든 경로/명령의 성공·실패를 빠짐없이 기록해서 로그로 남긴다.
    static func execute(_ category: CleanupCategory) -> Result {
        switch category.kind {
        case .npmCache:
            let (output, status) = Shell.run("/usr/bin/env", ["npm", "cache", "clean", "--force"])
            if status == 0 {
                return Result(categoryName: category.name, freedBytes: category.sizeBytes,
                              succeededCount: 1, failed: [], message: "npm 캐시 정리 완료")
            } else {
                return Result(categoryName: category.name, freedBytes: 0, succeededCount: 0,
                              failed: [PathError(path: "npm cache clean --force", error: output)],
                              message: "npm 캐시 정리 실패")
            }

        case .unusedSimulatorRuntimes:
            var succeeded = 0
            var failed: [PathError] = []
            for uuid in category.targetPaths {
                let (output, status) = Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "delete", uuid])
                if status == 0 {
                    succeeded += 1
                } else {
                    failed.append(PathError(path: uuid, error: output))
                }
            }
            let message = failed.isEmpty
                ? "\(succeeded)개 런타임 삭제 완료"
                : "\(succeeded)개 성공, \(failed.count)개 실패"
            return Result(categoryName: category.name,
                          freedBytes: failed.isEmpty ? category.sizeBytes : 0,
                          succeededCount: succeeded, failed: failed, message: message)

        case .coreSimulatorCache, .appCaches, .duplicateDownloads, .npxCache:
            return removePaths(category.targetPaths, name: category.name)

        case .nodeModules:
            var freed: Int64 = 0
            var succeeded = 0
            var failed: [PathError] = []
            var skippedInUse = 0
            for path in category.targetPaths {
                let projectDir = (path as NSString).deletingLastPathComponent
                guard !Shell.isPathInUse(projectDir) else { skippedInUse += 1; continue }
                let size = Shell.directorySizeBytes(path)
                do {
                    try FileManager.default.removeItem(atPath: path)
                    freed += size
                    succeeded += 1
                } catch {
                    failed.append(PathError(path: path, error: error.localizedDescription))
                }
            }
            var message = failed.isEmpty ? "정리 완료" : "\(failed.count)개 항목 삭제 실패"
            if skippedInUse > 0 { message += " (실행 중 감지되어 \(skippedInUse)개 제외)" }
            return Result(categoryName: category.name, freedBytes: freed,
                          succeededCount: succeeded, failed: failed, message: message)

        case .downloadsReviewOnly:
            return Result(categoryName: category.name, freedBytes: 0, succeededCount: 0,
                          failed: [], message: "자동 삭제 대상 아님 (직접 확인 필요)")
        }
    }

    private static func removePaths(_ paths: [String], name: String) -> Result {
        var freed: Int64 = 0
        var succeeded = 0
        var failed: [PathError] = []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let size = Shell.directorySizeBytes(path)
            do {
                try FileManager.default.removeItem(atPath: path)
                freed += size
                succeeded += 1
            } catch {
                failed.append(PathError(path: path, error: error.localizedDescription))
            }
        }
        let message = failed.isEmpty ? "정리 완료" : "\(failed.count)개 항목 삭제 실패"
        return Result(categoryName: name, freedBytes: freed, succeededCount: succeeded, failed: failed, message: message)
    }
}
