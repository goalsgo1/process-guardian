import Foundation

/// 기획서 6-1장의 위험도 3단계
enum CleanupTier {
    case safe       // 🟢 완전 자동 (재생성 가능)
    case verified   // 🟡 확인 후 자동 (동적 검증 통과 시)
    case manual     // 🔴 사용자 확인 필수 (기본 미체크)

    var badge: String {
        switch self {
        case .safe: return "🟢"
        case .verified: return "🟡"
        case .manual: return "🔴"
        }
    }
}

enum CleanupKind: Equatable {
    /// npm cache clean --force로 지운다 (~/.npm/_cacache 한정, _npx는 별도)
    case npmCache
    case unusedSimulatorRuntimes
    case coreSimulatorCache
    case duplicateDownloads
    case nodeModules
    case appCaches
    /// npx로 실행한 패키지 임시 캐시(~/.npm/_npx). npm cache clean이 안 건드리는 영역이라 별도 분리
    case npxCache
    /// 자동 성격 판단이 안 되는 항목 — 삭제 버튼 없이 Finder로만 열어줌
    case downloadsReviewOnly
}

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let tier: CleanupTier
    let kind: CleanupKind
    let detail: String
    var sizeBytes: Int64
    var isChecked: Bool
    var isBusy: Bool = false
    var targetPaths: [String] = []
    var skippedNote: String? = nil

    init(id: String, name: String, tier: CleanupTier, kind: CleanupKind, detail: String,
         sizeBytes: Int64, targetPaths: [String] = [], skippedNote: String? = nil) {
        self.id = id
        self.name = name
        self.tier = tier
        self.kind = kind
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.isChecked = tier != .manual
        self.targetPaths = targetPaths
        self.skippedNote = skippedNote
    }
}
