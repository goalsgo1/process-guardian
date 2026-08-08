import Foundation

/// Docker는 자동 스캔 대상에 넣지 않는다 — 데몬을 켜야 확인 가능하고, 켜는 것 자체가
/// 메모리를 더 먹어서 "디스크/메모리 압박 완화"라는 원래 목적과 상충하기 때문.
/// 그래서 버튼을 눌렀을 때만 켜고, 확인 후 바로 끈다. 이미지/볼륨은 절대 자동 삭제하지 않는다
/// (프로젝트 로컬 DB 등 실제 데이터일 수 있음 — 과거 한 프로젝트에서 겪은 실제 사례).
enum DockerHelper {
    static func isDaemonRunning() -> Bool {
        Shell.run("/usr/bin/env", ["docker", "info"]).status == 0
    }

    @discardableResult
    static func launchAndWait(timeoutSeconds: Int = 60) -> Bool {
        Shell.run("/usr/bin/open", ["-a", "Docker"])
        let interval = 2
        for _ in stride(from: 0, to: timeoutSeconds, by: interval) {
            if isDaemonRunning() { return true }
            Thread.sleep(forTimeInterval: TimeInterval(interval))
        }
        return isDaemonRunning()
    }

    /// 정지된 컨테이너/미사용 네트워크/댕글링 이미지만 정리. 이미지·볼륨·빌드캐시는 절대 안 지움(-a, --volumes 미사용)
    static func pruneSafe() -> (output: String, status: Int32) {
        Shell.run("/usr/bin/env", ["docker", "system", "prune", "-f"])
    }

    static func quit() {
        Shell.run("/usr/bin/osascript", ["-e", "tell application id \"com.docker.docker\" to quit"])
    }
}
