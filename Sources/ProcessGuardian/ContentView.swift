import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: CleanupViewModel

    var body: some View {
        if viewModel.showLogs {
            LogView(
                logs: viewModel.logs,
                logFilePath: viewModel.logFilePath,
                onBack: { viewModel.showLogs = false }
            )
        } else {
            mainView
        }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if viewModel.isScanning {
                ProgressView("스캔 중...")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if viewModel.categories.isEmpty {
                Text("정리할 항목이 없습니다")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($viewModel.categories) { $category in
                            CategoryRow(
                                category: $category,
                                onClean: { viewModel.confirmAndClean(categoryID: category.id) },
                                onOpenFinder: { viewModel.openDownloadsInFinder() }
                            )
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 440)
        .onAppear { viewModel.scanIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(viewModel.levelColor).frame(width: 10, height: 10)
                Text("디스크 사용률 \(viewModel.usedPercentText)")
                    .font(.headline)
                Spacer()
                Button("로그") { viewModel.showLogs = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                Button("새로고침") { viewModel.rescan() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            Text(viewModel.freeGBText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("선택 항목 총 \(viewModel.selectedSizeText)")
                .font(.subheadline)
            Spacer()
            Button("Docker 검사") { viewModel.inspectDocker() }
                .buttonStyle(.bordered)
            Button("전체 정리하기") { viewModel.confirmAndCleanSelected() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedTargets.isEmpty)
        }
    }
}

struct CategoryRow: View {
    @Binding var category: CleanupCategory
    let onClean: () -> Void
    let onOpenFinder: () -> Void

    var body: some View {
        HStack {
            if category.kind != .downloadsReviewOnly {
                Toggle("", isOn: $category.isChecked).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(category.tier.badge) \(category.name)")
                    .font(.body)
                Text(category.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = category.skippedNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(ByteFormatter.string(from: category.sizeBytes))
                .font(.caption)
                .monospacedDigit()
            Button(category.kind == .downloadsReviewOnly ? "Finder" : "정리") {
                if category.kind == .downloadsReviewOnly {
                    onOpenFinder()
                } else {
                    onClean()
                }
            }
            .buttonStyle(.bordered)
            .disabled(category.isBusy)
        }
        .padding(.vertical, 4)
    }
}
