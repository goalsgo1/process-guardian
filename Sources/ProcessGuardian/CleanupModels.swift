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
    /// 연결했던 기기의 디버그 심볼 캐시. Xcode가 필요할 때 다시 받는다
    case iosDeviceSupport
    /// 시뮬레이터 기기의 설치된 앱·데이터만 비움(이름·페어링은 유지) — xcrun simctl erase
    case simulatorErase
    /// 생성된 AVD가 참조하지 않는 Android system-image
    case androidSystemImages
    /// 현재 Flutter SDK 기본값이 아닌 구버전 Android NDK
    case androidOldNDK
    /// Claude 데스크톱 앱의 브라우저 엔진 캐시(대화 기록과 무관)
    case claudeAppCache
    /// Claude 로컬 샌드박스 실행용 리눅스 VM 이미지. 다음 사용 시 재다운로드됨
    case claudeVMBundles
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
