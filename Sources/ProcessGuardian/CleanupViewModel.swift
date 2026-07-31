import AppKit
import SwiftUI

final class CleanupViewModel: ObservableObject {
    @Published var categories: [CleanupCategory] = []
    @Published var isScanning = false
    @Published var diskStatus: DiskStatus?
    @Published var dockerStatusMessage: String = ""
    @Published var logs: [CleanupLogEntry] = []
    @Published var showLogs = false

    private var hasScannedOnce = false

    var logFilePath: String { CleanupLogStore.logFilePath }

    func reloadLogs() {
        logs = CleanupLogStore.loadAll()
    }

    var usedPercentText: String { "\(diskStatus?.usedPercent ?? 0)%" }

    var freeGBText: String {
        guard let bytes = diskStatus?.freeBytes else { return "-" }
        return String(format: "여유 %.1fGB", Double(bytes) / 1_073_741_824)
    }

    var levelColor: Color {
        switch diskStatus?.level {
        case .red: return .red
        case .yellow: return .yellow
        default: return .green
        }
    }

    var selectedTargets: [CleanupCategory] {
        categories.filter { $0.isChecked && $0.kind != .downloadsReviewOnly }
    }

    var selectedSizeText: String {
        ByteFormatter.string(from: selectedTargets.reduce(Int64(0)) { $0 + $1.sizeBytes })
    }

    func refreshDiskStatus() {
        diskStatus = DiskMonitor.currentStatus()
    }

    func scanIfNeeded() {
        reloadLogs()
        guard !hasScannedOnce else { return }
        rescan()
    }

    func rescan() {
        hasScannedOnce = true
        isScanning = true
        refreshDiskStatus()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = CleanupScanner.scanAll()
            DispatchQueue.main.async {
                self?.categories = result
                self?.isScanning = false
            }
        }
    }

    func confirmAndClean(categoryID: String) {
        guard let category = categories.first(where: { $0.id == categoryID }) else { return }
        guard confirmDeletion(count: 1, sizeText: ByteFormatter.string(from: category.sizeBytes)) else { return }
        run(categoryID: categoryID)
    }

    func confirmAndCleanSelected() {
        let targets = selectedTargets
        guard !targets.isEmpty else { return }
        guard confirmDeletion(count: targets.count, sizeText: selectedSizeText) else { return }
        for target in targets { run(categoryID: target.id) }
    }

    private func confirmDeletion(count: Int, sizeText: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(count)개 항목 정리"
        alert.informativeText = "총 \(sizeText) 삭제됩니다. 계속할까요?"
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func run(categoryID: String) {
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[index].isBusy = true
        let category = categories[index]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = CleanupExecutor.execute(category)
            let entry = CleanupLogEntry(
                timestamp: Date(),
                categoryID: category.id,
                categoryName: category.name,
                requestedBytes: category.sizeBytes,
                freedBytes: result.freedBytes,
                succeededCount: result.succeededCount,
                failed: result.failed,
                message: result.message
            )
            CleanupLogStore.append(entry)
            DispatchQueue.main.async {
                guard let self, let idx = self.categories.firstIndex(where: { $0.id == categoryID }) else { return }
                self.categories[idx].isBusy = false
                // 일부만 실패했으면 남은 용량을 그대로 보여줘서 재시도할 수 있게 함
                self.categories[idx].sizeBytes = max(0, category.sizeBytes - result.freedBytes)
                if result.isSuccess {
                    self.categories[idx].isChecked = false
                }
                self.refreshDiskStatus()
                self.reloadLogs()
            }
        }
    }

    func openDownloadsInFinder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Downloads"))
    }

    func inspectDocker() {
        dockerStatusMessage = "Docker 확인 중..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var startedHere = false
            if !DockerHelper.isDaemonRunning() {
                startedHere = DockerHelper.launchAndWait()
            }
            guard DockerHelper.isDaemonRunning() else {
                let entry = CleanupLogEntry(
                    timestamp: Date(), categoryID: "docker", categoryName: "Docker 정리",
                    requestedBytes: 0, freedBytes: 0, succeededCount: 0,
                    failed: [CleanupExecutor.PathError(path: "docker daemon", error: "60초 안에 실행되지 않음")],
                    message: "Docker 실행 실패"
                )
                CleanupLogStore.append(entry)
                DispatchQueue.main.async {
                    self?.dockerStatusMessage = "Docker 실행 실패"
                    self?.reloadLogs()
                }
                return
            }
            let (pruneOutput, pruneStatus) = DockerHelper.pruneSafe()
            if startedHere { DockerHelper.quit() }
            let entry = CleanupLogEntry(
                timestamp: Date(), categoryID: "docker", categoryName: "Docker 정리 (미사용 항목만)",
                requestedBytes: 0, freedBytes: 0, succeededCount: pruneStatus == 0 ? 1 : 0,
                failed: pruneStatus == 0 ? [] : [CleanupExecutor.PathError(path: "docker system prune -f", error: pruneOutput)],
                message: pruneStatus == 0 ? (pruneOutput.isEmpty ? "정리할 미사용 항목 없음" : pruneOutput) : "prune 실패"
            )
            CleanupLogStore.append(entry)
            DispatchQueue.main.async {
                self?.dockerStatusMessage = ""
                self?.reloadLogs()
                self?.showDockerAlert(prune: pruneOutput)
            }
        }
    }

    private func showDockerAlert(prune: String) {
        let alert = NSAlert()
        alert.messageText = "Docker 정리 결과"
        alert.informativeText = "이미지·볼륨은 보존했습니다 (프로젝트 로컬 DB 등 실제 데이터일 수 있어 자동 삭제 안 함).\n\n\(prune.isEmpty ? "정리할 미사용 항목 없음" : prune)"
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}
