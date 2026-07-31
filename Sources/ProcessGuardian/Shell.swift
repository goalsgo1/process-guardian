import Foundation

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ("", -1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }

    /// `du -sk`로 디렉토리/파일 용량(바이트)을 구한다. 존재하지 않으면 0.
    static func directorySizeBytes(_ path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let (output, status) = run("/usr/bin/du", ["-sk", path])
        guard status == 0 else { return 0 }
        let firstField = output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? "0"
        let kb = Int64(firstField.trimmingCharacters(in: .whitespaces)) ?? 0
        return kb * 1024
    }

    /// 해당 경로 하위에 열려있는 파일 핸들이 있으면 true (실행 중인 프로세스가 쓰고 있다는 뜻)
    static func isPathInUse(_ path: String) -> Bool {
        let (output, status) = run("/usr/sbin/lsof", ["+D", path])
        return status == 0 && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
