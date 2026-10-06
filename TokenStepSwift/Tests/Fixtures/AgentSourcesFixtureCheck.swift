import Foundation

// G-A1：T1 实验源校验（合成样本 + 可选真机只读验证）。
// 真机验证：TOKENSTEP_AGENT_SOURCES_REAL=1 时对真实 $HOME 只读采集并打印计数。
@main
struct AgentSourcesFixtureCheck {
    static func main() {
        do {
            try checkEnabledIDPolicy()
            try checkGemini()
            try checkQwen()
            try checkKimi()
            try checkGrok()
            try checkGeneric()
            try checkOpenCodeFallback()
            try checkTeleAgent()
            if ProcessInfo.processInfo.environment["TOKENSTEP_AGENT_SOURCES_REAL"] == "1" {
                reportRealMachine()
            }
            print("Agent sources fixture checks passed")
        } catch {
            fputs("Agent sources fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    // 开关语义（2026-08-13 用户裁决）：主开关开 + 未做逐源选择 → 已安装的源自动纳入。
    private static func checkEnabledIDPolicy() throws {
        let emptyHome = try freshDirectory("policy-empty")
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: false, perSource: nil, homeURL: emptyHome),
            [],
            "master off → empty"
        )
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: true, perSource: nil, homeURL: emptyHome),
            [],
            "master on + nothing installed → empty"
        )
        // 自动纳入：装有 Gemini 数据目录即自动启用 Gemini CLI。
        let geminiHome = try freshDirectory("policy-gemini")
        try FileManager.default.createDirectory(
            at: geminiHome.appendingPathComponent(".gemini/tmp/x/chats", isDirectory: true),
            withIntermediateDirectories: true
        )
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: true, perSource: nil, homeURL: geminiHome),
            ["Gemini CLI"],
            "detected agent auto-enrolls"
        )
        // 显式列表优先于自动纳入（用户可关掉自动源）。
        try expectEqual(
            AgentSourceRegistry.enabledIDs(
                masterEnabled: true,
                perSource: ["Grok Build", "NotARealSource"],
                homeURL: geminiHome
            ),
            ["Grok Build"],
            "explicit list filters unknown ids and overrides auto"
        )
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: false, perSource: ["Gemini CLI"], homeURL: geminiHome),
            [],
            "per-source cannot bypass master switch"
        )
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: true, perSource: [], homeURL: geminiHome),
            [],
            "explicit empty list disables every experimental source"
        )
    }

    // Gemini：本机真实 schema（session-*.json，tokens 分量）。
    private static func checkGemini() throws {
        let home = try freshDirectory("gemini")
        let chats = home.appendingPathComponent(".gemini/tmp/hash1/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let session: [String: Any] = [
            "sessionId": "s1",
            "startTime": "2026-08-13T01:00:00Z",
            "messages": [
                ["type": "user", "content": "hi", "timestamp": "2026-08-13T01:00:01Z"],
                [
                    "type": "gemini",
                    "id": "m1",
                    "model": "gemini-2.5-pro",
                    "timestamp": "2026-08-13T01:01:00Z",
                    "tokens": ["input": 8095, "output": 9, "cached": 100, "thoughts": 33, "tool": 0, "total": 8137]
                ]
            ] as [Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: session, options: [.sortedKeys])
        try data.write(to: chats.appendingPathComponent("session-2026-08-13-x.json"))
        let result = GeminiCLISource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "gemini status")
        try expectEqual(result.records.count, 1, "gemini record count")
        try expectEqual(result.records[0].model, "gemini-2.5-pro", "gemini model")
        try expectEqual(result.records[0].usage.totalTokens, 8137, "gemini explicit total")
        try expectEqual(result.records[0].usage.cacheReadInputTokens, 100, "gemini cached")
    }

    // Qwen：usageMetadata（Gemini 分叉 schema，公开情报）。
    private static func checkQwen() throws {
        let home = try freshDirectory("qwen")
        let dir = home.appendingPathComponent(".qwen/tmp/p1", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line: [String: Any] = [
            "timestamp": 1_800_000_000.0,
            "usageMetadata": [
                "promptTokenCount": 1000,
                "candidatesTokenCount": 100,
                "cachedContentTokenCount": 400,
                "thoughtsTokenCount": 50
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: dir.appendingPathComponent("session-1.jsonl"), atomically: true, encoding: .utf8)
        let result = QwenCodeSource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "qwen status")
        try expectEqual(result.records[0].usage.totalTokens, 1100, "qwen total")
        try expectEqual(result.records[0].usage.cacheReadInputTokens, 400, "qwen cached subset")
    }

    // Kimi：新版 wire usage.record（公开情报）；旧版无 usage 事件 → missing_valid_rows。
    private static func checkKimi() throws {
        let home = try freshDirectory("kimi")
        let wireDir = home.appendingPathComponent(".kimi-code/sessions/wd_a/session_x/agents/main", isDirectory: true)
        try FileManager.default.createDirectory(at: wireDir, withIntermediateDirectories: true)
        let lines = [
            "{\"type\": \"metadata\", \"protocol_version\": \"1.1\"}",
            "{\"timestamp\": 1800000000.5, \"message\": {\"type\": \"UsageRecord\", \"payload\": {\"model\": \"kimi-k2\", \"cwd\": \"/u/p/kimi-app\", \"usage\": {\"input_tokens\": 500, \"output_tokens\": 50, \"cache_read_tokens\": 200}}}}"
        ]
        try lines.joined(separator: "\n").appending("\n")
            .write(to: wireDir.appendingPathComponent("wire.jsonl"), atomically: true, encoding: .utf8)
        let result = KimiCodeSource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "kimi status")
        try expectEqual(result.records[0].usage.totalTokens, 750, "kimi total input(+cache)+output")
        try expectEqual(result.records[0].projectName, "kimi-app", "kimi project from cwd")

        // 旧版 .kimi：无 usage 事件，如实无数据。
        let legacyHome = try freshDirectory("kimi-legacy")
        let legacyDir = legacyHome.appendingPathComponent(".kimi/sessions/x/y", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try "{\"timestamp\":1,\"message\":{\"type\":\"TurnBegin\",\"payload\":{}}}\n"
            .write(to: legacyDir.appendingPathComponent("wire.jsonl"), atomically: true, encoding: .utf8)
        let legacy = KimiCodeSource.collect(homeURL: legacyHome)
        try expectEqual(legacy.source.status, "missing", "legacy .kimi not scanned (no usage events)")
    }

    // Grok：本机真实 schema（updates.jsonl + URL 编码项目目录）。
    private static func checkGrok() throws {
        let home = try freshDirectory("grok")
        let encoded = "%2FUsers%2Fbench%2Fdev%2Fgrok-app"
        let dir = home.appendingPathComponent(".grok/sessions/\(encoded)/019f9153-aaaa", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line: [String: Any] = [
            "timestamp": 1_800_000_000,
            "method": "_x.ai/session/update",
            "params": [
                "sessionId": "019f9153-aaaa",
                "update": [
                    "sessionUpdate": "turn_completed",
                    "prompt_id": "p1",
                    "usage": [
                        "inputTokens": 958_154,
                        "outputTokens": 15_174,
                        "totalTokens": 973_328,
                        "cachedReadTokens": 855_296,
                        "reasoningTokens": 8_868,
                        "modelUsage": ["grok-4.5-build": ["inputTokens": 1]] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: dir.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        let result = GrokBuildSource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "grok status")
        try expectEqual(result.records[0].usage.totalTokens, 973_328, "grok explicit total")
        try expectEqual(result.records[0].model, "grok-4.5-build", "grok model from modelUsage")
        try expectEqual(result.records[0].projectName, "grok-app", "grok project from encoded dir")
        // 重复 prompt_id 去重。
        try (String(data: data, encoding: .utf8)! + "\n")
            .write(to: dir.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        let deduped = GrokBuildSource.collect(homeURL: home)
        try expectEqual(deduped.records.count, 1, "grok dedup by prompt_id")
    }

    // Amp / Droid：通用 usage 行提取。
    private static func checkGeneric() throws {
        let home = try freshDirectory("amp")
        let dir = home.appendingPathComponent(".local/share/amp/threads/t1", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{\"timestamp\":1800000000,\"cwd\":\"/u/p/amp-app\",\"model\":\"amp-1\",\"usage\":{\"input_tokens\":100,\"output_tokens\":10,\"cached_input_tokens\":30}}\n"
            .write(to: dir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        let result = AgentSourceRegistry.collect(enabledIDs: ["Amp"], homeURL: home)["Amp"]
        try expectEqual(result?.source.status, "ok", "amp status")
        try expectEqual(result?.records.first?.usage.totalTokens, 140, "amp total")
        try expectEqual(result?.records.first?.projectName, "amp-app", "amp project")

        let missing = AgentSourceRegistry.collect(enabledIDs: ["Droid"], homeURL: home)["Droid"]
        try expectEqual(missing?.source.status, "missing", "droid missing without factory dir")
    }

    // OpenCode：无 DB → missing_db；真实 DB 走真机验证路径。
    private static func checkOpenCodeFallback() throws {
        let home = try freshDirectory("opencode")
        let result = OpenCodeSource.collect(homeURL: home)
        try expectEqual(result.source.status, "missing_db", "opencode missing db")
    }

    // TeleAgent 2.2.1：OpenCode 兼容 message.data tokens；项目优先取 session.directory。
    private static func checkTeleAgent() throws {
        let home = try freshDirectory("teleagent")
        let directory = home.appendingPathComponent(".local/share/TeleAgent", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("teleagent.db")
        let assistant: [String: Any] = [
            "role": "assistant",
            "modelID": "chat-pro",
            "path": ["cwd": "/Users/bench/work/stale-message-cwd"],
            "tokens": [
                "input": 100,
                "output": 20,
                "reasoning": 5,
                "cache": ["read": 80, "write": 20],
                "total": 220
            ] as [String: Any]
        ]
        let user: [String: Any] = ["role": "user"]
        let assistantJSON = try jsonString(assistant)
        let userJSON = try jsonString(user)
        try runSQLite(database, sql: """
        create table session (
          id text primary key,
          directory text not null
        );
        create table message (
          id text primary key,
          session_id text not null,
          time_created integer not null,
          time_updated integer not null,
          data text not null
        );
        insert into session values ('ses-1', '/Users/bench/work/tele-workspace');
        insert into message values
          ('msg-assistant', 'ses-1', 1800000000000, 1800000000000, '\(assistantJSON)'),
          ('msg-user', 'ses-1', 1799999999000, 1799999999000, '\(userJSON)');
        """)

        let detected = AgentSourceRegistry.observeAll(homeURL: home)
            .first(where: { $0.sourceID == AgentSourceRegistry.teleAgent })
        try expectEqual(detected?.status, "installed", "teleagent detection")
        try expectEqual(
            AgentSourceRegistry.enabledIDs(masterEnabled: true, perSource: nil, homeURL: home),
            ["TeleAgent"],
            "teleagent auto-enrolls when experimental sources are enabled"
        )

        let result = TeleAgentSource.collect(homeURL: home)
        try expectEqual(result.source.status, "ok", "teleagent status")
        try expectEqual(result.records.count, 1, "teleagent assistant-only record count")
        try expectEqual(result.records[0].tool, "TeleAgent", "teleagent tool")
        try expectEqual(result.records[0].model, "chat-pro", "teleagent model")
        try expectEqual(result.records[0].usage.totalTokens, 220, "teleagent explicit total")
        try expectEqual(result.records[0].usage.cacheReadInputTokens, 80, "teleagent cache read")
        try expectEqual(result.records[0].usage.cacheCreationInputTokens, 20, "teleagent cache write")
        try expectEqual(result.records[0].projectName, "tele-workspace", "teleagent session directory project")
    }

    // 真机只读验证（打印计数供 G-A1 证据）。
    private static func reportRealMachine() {
        let observations = AgentSourceRegistry.observeAll()
        for observation in observations {
            print("real \(observation.sourceID)=\(observation.status)")
        }
        let results = AgentSourceRegistry.collect(enabledIDs: AgentSourceRegistry.allSourceIDs)
        for (name, result) in results.sorted(by: { $0.key < $1.key }) {
            let tokens = result.records.reduce(0) { $0 + $1.usage.totalTokens }
            print("real-collect \(name) status=\(result.source.status ?? "unknown") records=\(result.records.count) tokens=\(tokens)")
            if name == AgentSourceRegistry.teleAgent {
                let projects = Dictionary(grouping: result.records, by: { $0.projectName ?? "" })
                    .mapValues { $0.reduce(0) { $0 + $1.usage.totalTokens } }
                for (project, projectTokens) in projects.sorted(by: { $0.value > $1.value }) {
                    print("real-collect TeleAgent project=\(project.isEmpty ? "(unnamed)" : project) tokens=\(projectTokens)")
                }
            }
        }
        let snapshot = UsageCollector.collect(
            historyDays: 180,
            includeCCSwitchProxyUsage: false,
            includeExperimentalAgentSources: true,
            experimentalAgentSourceIDs: [AgentSourceRegistry.teleAgent],
            forceFullValidation: false
        )
        for project in snapshot.projects where (project.tools[AgentSourceRegistry.teleAgent] ?? 0) > 0 {
            print("real-snapshot TeleAgent project=\(project.name.isEmpty ? "(unnamed)" : project.name) tokens=\(project.tools[AgentSourceRegistry.teleAgent] ?? 0)")
        }
    }

    private static func freshDirectory(_ label: String) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("TokenStepAgentSources-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return (String(data: data, encoding: .utf8) ?? "{}")
            .replacingOccurrences(of: "'", with: "''")
    }

    private static func runSQLite(_ database: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "sqlite fixture failed"
            throw FixtureFailure(message)
        }
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    guard actual == expected else {
        throw FixtureFailure("\(label): expected \(expected), got \(actual)")
    }
}

private struct FixtureFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
