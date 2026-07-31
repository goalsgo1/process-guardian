import AppKit
import SwiftUI

private let dateKeyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

struct LogView: View {
    let logs: [CleanupLogEntry]
    let logFilePath: String
    let onBack: () -> Void

    @State private var selectedDate: String = "all"
    @State private var selectedCategory: String = "all"
    @State private var captureMessage: String = ""

    private var availableDates: [String] {
        Array(Set(logs.map { dateKeyFormatter.string(from: $0.timestamp) })).sorted(by: >)
    }

    private var availableCategories: [String] {
        Array(Set(logs.map { $0.categoryName })).sorted()
    }

    private var filteredLogs: [CleanupLogEntry] {
        logs.filter { entry in
            let dateMatches = selectedDate == "all" || dateKeyFormatter.string(from: entry.timestamp) == selectedDate
            let categoryMatches = selectedCategory == "all" || entry.categoryName == selectedCategory
            return dateMatches && categoryMatches
        }
    }

    /// "전체 정리하기" 한 번 누르면 여러 항목이 몇 초 간격으로 기록되는데, 그걸 하나의
    /// 세션으로 묶는다. 세션 간 기준은 30초 — 그보다 오래 벌어지면 별도 실행으로 간주.
    private var sessions: [[CleanupLogEntry]] {
        let chronological = filteredLogs.sorted { $0.timestamp < $1.timestamp }
        guard !chronological.isEmpty else { return [] }
        let gapThreshold: TimeInterval = 30
        var groups: [[CleanupLogEntry]] = []
        var current: [CleanupLogEntry] = [chronological[0]]
        for entry in chronological.dropFirst() {
            if let last = current.last, entry.timestamp.timeIntervalSince(last.timestamp) <= gapThreshold {
                current.append(entry)
            } else {
                groups.append(current)
                current = [entry]
            }
        }
        groups.append(current)
        // 최신 세션이 위로, 세션 내부도 최신 항목이 위로 오도록 정렬
        return groups.reversed().map { $0.reversed() }
    }

    private func sessionHeader(_ session: [CleanupLogEntry]) -> String {
        guard let earliest = session.map({ $0.timestamp }).min(),
              let latest = session.map({ $0.timestamp }).max() else { return "" }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "MM/dd HH:mm:ss"
        let onlyTimeFormatter = DateFormatter()
        onlyTimeFormatter.dateFormat = "HH:mm:ss"
        let rangeText = earliest == latest
            ? timeFormatter.string(from: earliest)
            : "\(timeFormatter.string(from: earliest)) ~ \(onlyTimeFormatter.string(from: latest))"
        let freedTotal = session.reduce(Int64(0)) { $0 + $1.freedBytes }
        let failedCount = session.reduce(0) { $0 + $1.failed.count }
        let statusIcon = failedCount == 0 ? "✅" : "⚠️"
        return "\(statusIcon) \(rangeText) · \(session.count)개 · 확보 \(ByteFormatter.string(from: freedTotal))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("〈 뒤로") { onBack() }.buttonStyle(.plain)
                Spacer()
                Text("정리 로그").font(.headline)
                Spacer()
                Button("파일 열기") {
                    NSWorkspace.shared.selectFile(logFilePath, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            if logs.isEmpty {
                Text("아직 기록된 로그가 없습니다")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                filterRow

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if filteredLogs.isEmpty {
                            Text("이 조건에 맞는 기록이 없습니다")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60)
                        } else {
                            ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                                SessionGroup(
                                    header: sessionHeader(session),
                                    entries: session,
                                    onCapture: { captureSession(session) }
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)

                HStack {
                    Text("\(filteredLogs.count)개 항목")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("이 조건으로 캡쳐") { capture() }
                        .buttonStyle(.bordered)
                        .disabled(filteredLogs.isEmpty)
                }

                if !captureMessage.isEmpty {
                    Text(captureMessage)
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }
            }

            Divider()
            Text("캡쳐 파일이나 이 경로를 Claude에게 보여주면 실행 결과를 확인해줄 수 있어요")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(logFilePath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(width: 440)
    }

    private var filterRow: some View {
        HStack {
            Picker("", selection: $selectedDate) {
                Text("전체 날짜").tag("all")
                ForEach(availableDates, id: \.self) { date in
                    Text(date).tag(date)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 150)

            Picker("", selection: $selectedCategory) {
                Text("전체 항목").tag("all")
                ForEach(availableCategories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Spacer()
        }
    }

    /// 보이는 스크롤 영역과 무관하게, 필터링된 세션 전체를 하나의 이미지로 렌더링해서 저장한다.
    /// 팝오버 화면 캡쳐로는 스크롤 밖 내용이 안 잡히는 문제를 이렇게 우회한다.
    private func capture() {
        let sessionsToCapture = sessions
        guard !sessionsToCapture.isEmpty else { return }

        let title = "정리 로그 — \(selectedDate == "all" ? "전체 날짜" : selectedDate) · \(selectedCategory == "all" ? "전체 항목" : selectedCategory)"
        let content = VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).padding(.bottom, 4)
            ForEach(Array(sessionsToCapture.enumerated()), id: \.offset) { _, session in
                SessionGroup(header: sessionHeader(session), entries: session)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))

        saveRenderedImage(content)
    }

    /// 세션 하나만 캡쳐 — 헤더의 [캡쳐] 버튼에서 호출됨
    private func captureSession(_ session: [CleanupLogEntry]) {
        guard !session.isEmpty else { return }
        let content = VStack(alignment: .leading, spacing: 8) {
            Text("정리 로그 세션 — \(sessionHeader(session))").font(.headline).padding(.bottom, 4)
            ForEach(session) { entry in
                LogRow(entry: entry)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))

        saveRenderedImage(content)
    }

    private func saveRenderedImage<Content: View>(_ content: Content) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            captureMessage = "캡쳐 실패"
            return
        }

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProcessGuardian/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = dateKeyFormatter.string(from: Date()) + "_" + String(Int(Date().timeIntervalSince1970))
        let fileURL = dir.appendingPathComponent("cleanup-log-\(stamp).png")

        do {
            try png.write(to: fileURL)
            captureMessage = "저장됨: \(fileURL.path)"
            NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
        } catch {
            captureMessage = "캡쳐 저장 실패: \(error.localizedDescription)"
        }
    }
}

struct SessionGroup: View {
    let header: String
    let entries: [CleanupLogEntry]
    var onCapture: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(header)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let onCapture {
                    Spacer()
                    Button("캡쳐") { onCapture() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    LogRow(entry: entry)
                }
            }
            .padding(.leading, 8)
        }
    }
}

struct LogRow: View {
    let entry: CleanupLogEntry

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.isSuccess ? "✅" : "⚠️")
                Text(entry.categoryName).font(.body)
                Spacer()
                Text(Self.formatter.string(from: entry.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("확보 \(ByteFormatter.string(from: entry.freedBytes)) · \(entry.message)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(entry.failed, id: \.path) { failure in
                Text("실패: \(failure.path) — \(failure.error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
        .textSelection(.enabled)
    }
}
