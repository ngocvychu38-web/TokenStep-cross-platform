import Foundation

enum ManualUsageRefreshService {
    static func collectAndUpload(projectURL: String) async throws {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/TokenStep/agent")
        guard let endpoint = URL(string: projectURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/functions/v1/ingest-usage"), endpoint.scheme == "https" else {
            throw RefreshError.invalidEndpoint
        }
        try await Task.detached(priority: .utility) {
            try run(executable: root.appendingPathComponent("bin/tokenstep-agent"), state: root, endpoint: endpoint.absoluteString)
        }.value
    }

    // Uses the installed credential-authorized agent; never reads credentials or local usage into the UI.
    static func run(executable: URL, state: URL, endpoint: String, timeout: TimeInterval = 120) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw RefreshError.missingAgent }
        let logs = state.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("manual-refresh.log")
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let offset = try output.seekToEnd()
            let process = Process()
            process.executableURL = executable
            process.arguments = ["cycle", "--state-dir", state.path, "--ingest-url", endpoint]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if process.isRunning {
                process.terminate()
                throw RefreshError.timedOut
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw RefreshError.agentFailed }
            let input = try FileHandle(forReadingFrom: log)
            defer { try? input.close() }
            try input.seek(toOffset: offset)
            let text = String(decoding: try input.readToEnd() ?? Data(), as: UTF8.self)
            if text.contains("cycle_ok at=") { return }
            guard text.contains("cycle_skipped already_running") else { throw RefreshError.agentFailed }
            // Wait for the scheduled cycle's lock, then run our own fresh cycle instead of reading stale data.
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw RefreshError.timedOut
    }

    enum RefreshError: LocalizedError {
        case invalidEndpoint, missingAgent, agentFailed, timedOut
        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return L("请先配置 Supabase HTTPS 地址")
            case .missingAgent: return L("未安装本机采集代理，请先安装代理")
            case .agentFailed: return L("本机采集或上传失败，请查看 manual-refresh.log")
            case .timedOut: return L("刷新超时，请检查网络或钥匙串授权")
            }
        }
    }
}
