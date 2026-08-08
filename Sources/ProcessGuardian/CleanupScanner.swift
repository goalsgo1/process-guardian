import Foundation

enum CleanupScanner {
    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    static func scanAll() -> [CleanupCategory] {
        var categories: [CleanupCategory] = []
        categories.append(scanNpmCache())
        categories.append(scanNpxCache())
        if let runtimes = scanUnusedSimulatorRuntimes() { categories.append(runtimes) }
        categories.append(scanCoreSimulatorCache())
        categories.append(contentsOf: scanNodeModules())
        let duplicateDownloads = scanDuplicateDownloads()
        categories.append(duplicateDownloads)
        categories.append(scanAppCaches())
        categories.append(scanDownloadsReviewOnly(excluding: Set(duplicateDownloads.targetPaths)))
        return categories
    }

    // MARK: - 🟢 npm 캐시

    private static func scanNpmCache() -> CleanupCategory {
        // ~/.npm 전체가 아니라 _cacache만 재야 정확함. ~/.npm에는 npm cache clean이
        // 안 건드리는 _npx(아래 scanNpxCache)가 같이 있어서, 전체를 재면 정리해도
        // 크기가 안 줄어드는 것처럼 보이는 버그가 생김.
        let path = "\(home)/.npm/_cacache"
        return CleanupCategory(
            id: "npm-cache", name: "npm 캐시", tier: .safe, kind: .npmCache,
            detail: "npm install 시 재생성됩니다",
            sizeBytes: Shell.directorySizeBytes(path), targetPaths: [path]
        )
    }

    private static func scanNpxCache() -> CleanupCategory {
        let path = "\(home)/.npm/_npx"
        return CleanupCategory(
            id: "npx-cache", name: "npx 캐시", tier: .safe, kind: .npxCache,
            detail: "npx로 실행했던 패키지 임시 캐시입니다. 다음 실행 시 다시 받습니다",
            sizeBytes: Shell.directorySizeBytes(path), targetPaths: [path]
        )
    }

    // MARK: - 🟡 안 쓰는 시뮬레이터 런타임

    /// 현재 등록된 시뮬레이터 기기가 실제로 쓰는 런타임을 "iOS 26.5" 같은 버전 문자열로 수집
    private static func usedRuntimeVersionStrings() -> Set<String> {
        let (json, status) = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"])
        guard status == 0, let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = root["devices"] as? [String: Any] else { return [] }

        let pattern = try! NSRegularExpression(pattern: "SimRuntime\\.([A-Za-z]+)-(\\d+)-(\\d+)")
        var result = Set<String>()
        for (runtimeKey, value) in devices {
            guard let list = value as? [[String: Any]], !list.isEmpty else { continue }
            let range = NSRange(runtimeKey.startIndex..., in: runtimeKey)
            guard let match = pattern.firstMatch(in: runtimeKey, range: range),
                  let osRange = Range(match.range(at: 1), in: runtimeKey),
                  let majorRange = Range(match.range(at: 2), in: runtimeKey),
                  let minorRange = Range(match.range(at: 3), in: runtimeKey) else { continue }
            result.insert("\(runtimeKey[osRange]) \(runtimeKey[majorRange]).\(runtimeKey[minorRange])")
        }
        return result
    }

    private static func scanUnusedSimulatorRuntimes() -> CleanupCategory? {
        let used = usedRuntimeVersionStrings()
        let (listOutput, status) = Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list"])
        guard status == 0 else { return nil }

        var unusedIDs: [String] = []
        var unusedNames: [String] = []
        for rawLine in listOutput.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains(" - "), line.contains("(Ready)"), let parenIndex = line.firstIndex(of: "(") else { continue }
            let versionString = line[line.startIndex..<parenIndex].trimmingCharacters(in: .whitespaces)
            guard !used.contains(versionString), let dashRange = line.range(of: " - ") else { continue }
            guard let uuid = line[dashRange.upperBound...].split(separator: " ").first else { continue }
            unusedIDs.append(String(uuid))
            unusedNames.append(versionString)
        }
        guard !unusedIDs.isEmpty else { return nil }

        // 정확한 런타임별 용량 산출은 API 한계로 어려워, 전체 볼륨 크기로 근사함
        let approxSize = Shell.directorySizeBytes("/Library/Developer/CoreSimulator/Volumes")
        return CleanupCategory(
            id: "sim-runtimes",
            name: "안 쓰는 시뮬레이터 런타임 (\(unusedNames.joined(separator: ", ")))",
            tier: .verified, kind: .unusedSimulatorRuntimes,
            detail: "현재 등록된 시뮬레이터 기기가 쓰지 않는 런타임입니다. 필요하면 Xcode에서 재설치 가능 (용량은 전체 시뮬레이터 볼륨 기준 근사치)",
            sizeBytes: approxSize, targetPaths: unusedIDs
        )
    }

    // MARK: - 🟢 CoreSimulator 캐시 (SIP 보호 경로 제외)

    private static func scanCoreSimulatorCache() -> CleanupCategory {
        let basePath = "/Library/Developer/CoreSimulator/Caches"
        var total: Int64 = 0
        var targets: [String] = []
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: basePath) {
            for entry in entries where entry != "dyld" {
                let full = "\(basePath)/\(entry)"
                total += Shell.directorySizeBytes(full)
                targets.append(full)
            }
        }
        return CleanupCategory(
            id: "coresim-cache", name: "CoreSimulator 캐시", tier: .safe, kind: .coreSimulatorCache,
            detail: "시뮬레이터 실행 캐시입니다",
            sizeBytes: total, targetPaths: targets,
            skippedNote: "dyld 하위 폴더는 SIP(시스템 무결성 보호) 대상이라 제외했습니다"
        )
    }

    // MARK: - 🟡 node_modules

    // launchd/cron으로 하루 중 짧게만 돌아가는 무인 파이프라인 프로젝트는 스캔 시점에
    // 거의 항상 "사용 중 아님"으로 보여서 verified 티어(기본 자동삭제)로 잘못 분류된다.
    // 판단 기준은 프로젝트 이름을 하드코딩하지 않고, ~/Library/LaunchAgents에 그 경로를
    // 참조하는 launchd job이 있는지로 동적으로 판별한다 — 이 저장소는 공개 GitHub repo라
    // 개인 프로젝트 이름을 소스에 박아두면 안 됨.
    private static func hasLaunchdJob(referencingPath projectPath: String) -> Bool {
        let launchAgentsDir = "\(home)/Library/LaunchAgents"
        guard let plists = try? FileManager.default.contentsOfDirectory(atPath: launchAgentsDir) else { return false }
        for name in plists where name.hasSuffix(".plist") {
            guard let contents = try? String(contentsOfFile: "\(launchAgentsDir)/\(name)", encoding: .utf8) else { continue }
            if contents.contains(projectPath) { return true }
        }
        return false
    }

    private static func scanNodeModules() -> [CleanupCategory] {
        let projectsRoot = "\(home)/MyWorkspace/projects"
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(atPath: projectsRoot) else { return [] }

        var categories: [CleanupCategory] = []
        for projectName in projectDirs {
            let projectPath = "\(projectsRoot)/\(projectName)"
            guard let found = findNodeModules(under: projectPath, maxDepth: 3) else { continue }
            for nodeModulesPath in found {
                let size = Shell.directorySizeBytes(nodeModulesPath)
                guard size > 10_000_000 else { continue } // 10MB 미만은 노출 안 함
                let projectDir = (nodeModulesPath as NSString).deletingLastPathComponent
                let isUnattended = hasLaunchdJob(referencingPath: projectPath)
                let inUse = isUnattended || Shell.isPathInUse(projectDir)
                categories.append(CleanupCategory(
                    id: "node-modules-\(nodeModulesPath)",
                    name: "node_modules (\(projectName))",
                    tier: inUse ? .manual : .verified,
                    kind: .nodeModules,
                    detail: isUnattended
                        ? "무인 파이프라인 프로젝트라 항상 수동 확인이 필요합니다. npm install로 재생성됩니다"
                        : (inUse
                            ? "실행 중인 프로세스가 감지되어 기본적으로 제외했습니다. npm install로 재생성됩니다"
                            : "npm install로 재생성됩니다"),
                    sizeBytes: size,
                    targetPaths: [nodeModulesPath]
                ))
            }
        }
        return categories
    }

    private static func findNodeModules(under path: String, maxDepth: Int) -> [String]? {
        guard maxDepth > 0 else { return nil }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return nil }

        var results: [String] = []
        if entries.contains("node_modules") {
            results.append("\(path)/node_modules")
        }
        for entry in entries where entry != "node_modules" && !entry.hasPrefix(".") {
            let full = "\(path)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
            if let nested = findNodeModules(under: full, maxDepth: maxDepth - 1) {
                results.append(contentsOf: nested)
            }
        }
        return results.isEmpty ? nil : results
    }

    // MARK: - 🟡 Downloads 중복 설치파일

    private static func scanDuplicateDownloads() -> CleanupCategory {
        let downloadsPath = "\(home)/Downloads"
        let installedApps = installedApplicationNames()
        var targets: [String] = []
        var total: Int64 = 0

        if let entries = try? FileManager.default.contentsOfDirectory(atPath: downloadsPath) {
            for entry in entries {
                let ext = (entry as NSString).pathExtension.lowercased()
                guard ["dmg", "pkg", "zip", "app"].contains(ext) else { continue }
                let normalizedEntry = normalize(entry)
                guard installedApps.contains(where: {
                    let normalizedApp = normalize($0)
                    return normalizedApp.contains(normalizedEntry) || normalizedEntry.contains(normalizedApp)
                }) else { continue }
                let full = "\(downloadsPath)/\(entry)"
                targets.append(full)
                total += Shell.directorySizeBytes(full)
            }
        }
        return CleanupCategory(
            id: "downloads-dup", name: "Downloads 중복 설치파일 (\(targets.count)개)", tier: .verified,
            kind: .duplicateDownloads,
            detail: "/Applications에 이미 설치된 것으로 보이는 설치파일입니다. 정리 전 목록을 확인하세요",
            sizeBytes: total, targetPaths: targets
        )
    }

    private static func installedApplicationNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: "/Applications"))?
            .filter { $0.hasSuffix(".app") }
            .map { $0.replacingOccurrences(of: ".app", with: "") } ?? []
    }

    private static func normalize(_ name: String) -> String {
        var stripped = (name as NSString).deletingPathExtension.lowercased()
        stripped = stripped.replacingOccurrences(of: "-darwin-universal", with: "")
        stripped.removeAll { "0123456789.-_ ".contains($0) }
        return stripped
    }

    // MARK: - 🟢 앱 캐시

    private static func scanAppCaches() -> CleanupCategory {
        let cachesRoot = "\(home)/Library/Caches"
        let knownSafe = [
            "com.microsoft.VSCode.ShipIt",
            "Google",
            "com.apple.python",
            "ru.keepcoder.Telegram",
            "pip",
            "node-gyp"
        ]
        var targets: [String] = []
        var total: Int64 = 0
        for name in knownSafe {
            let full = "\(cachesRoot)/\(name)"
            guard FileManager.default.fileExists(atPath: full) else { continue }
            targets.append(full)
            total += Shell.directorySizeBytes(full)
        }
        return CleanupCategory(
            id: "app-caches", name: "앱 캐시 (VSCode/Chrome/Telegram/pip 등)", tier: .safe, kind: .appCaches,
            detail: "각 앱이 다시 만들어내는 임시 캐시입니다",
            sizeBytes: total, targetPaths: targets
        )
    }

    // MARK: - 🔴 Downloads 그 외 (자동 판단 불가, Finder로만 열기)

    private static func scanDownloadsReviewOnly(excluding: Set<String>) -> CleanupCategory {
        let downloadsPath = "\(home)/Downloads"
        var targets: [String] = []
        var total: Int64 = 0
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: downloadsPath) {
            for entry in entries where !entry.hasPrefix(".") {
                let full = "\(downloadsPath)/\(entry)"
                guard !excluding.contains(full) else { continue }
                let size = Shell.directorySizeBytes(full)
                guard size > 20_000_000 else { continue } // 20MB 미만은 노출 안 함
                targets.append(full)
                total += size
            }
        }
        return CleanupCategory(
            id: "downloads-review", name: "Downloads 그 외 큰 항목 (\(targets.count)개)", tier: .manual,
            kind: .downloadsReviewOnly,
            detail: "자동으로 성격을 판단할 수 없는 파일입니다. 직접 확인 후 정리하세요 (개인데이터·미통합 프로젝트 자산일 수 있음)",
            sizeBytes: total, targetPaths: targets
        )
    }
}
