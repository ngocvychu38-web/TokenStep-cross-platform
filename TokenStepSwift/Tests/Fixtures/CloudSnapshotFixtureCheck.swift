import Foundation

@main
struct CloudSnapshotFixtureCheck {
    @MainActor static func main() async throws {
        let iso = ISO8601DateFormatter()
        let mayStart = iso.date(from: "2026-04-30T16:00:00Z")!
        let mayEnd = iso.date(from: "2026-05-10T15:59:59Z")!
        let range = CloudDateRange(start: mayStart, end: mayEnd)
        precondition(range.startDay == "2026-05-01" && range.endDay == "2026-05-10")
        precondition(range.contains("2026-05-01") && range.contains("2026-05-10"))
        precondition(range.contains("2026-05-05"))
        precondition(!range.contains("2026-04-30") && !range.contains("2026-05-11"))
        precondition(CloudDateRange(start: mayStart, end: mayStart).contains("2026-05-01"))
        precondition(CloudDateRange(start: mayEnd, end: mayStart).startDay == range.startDay)
        print("cloud_date_range_ok: inclusive boundaries, single day, reversed dates, Shanghai timezone")
        let json = """
        [{"workspace_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","local_date":"2026-10-07","device_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","device_name":"Intel Mac","os_family":"macos","os_version":"26","architecture":"x86_64","agent_key":"teleagent","agent_name":"TeleAgent","project_key":"p1","project_name":"tokenhub","model":"gpt-5","input_tokens":10,"output_tokens":4,"cache_read_tokens":3,"cache_write_tokens":1,"reasoning_tokens":2,"total_tokens":18,"record_count":1,"last_seen_at":"2026-10-07T01:00:00Z","hourly_usage":[{"hour":9,"record_count":1,"tokens":{"input_tokens":10,"output_tokens":4,"cache_read_tokens":3,"cache_write_tokens":1,"reasoning_tokens":2,"total_tokens":18}}]}]
        """
        var rows = try JSONDecoder().decode([CloudUsageRow].self, from: Data(json.utf8))
        var second = rows[0]
        second.deviceID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        second.deviceName = "Windows"
        second.osFamily = "windows"
        rows.append(second)
        rows.append(rows[0]) // Accidental duplicate pagination must not double count.
        let result = CloudSnapshotAdapter.snapshot(rows: rows)
        precondition(result.totals.tokens == 36)
        precondition(abs(result.totals.cost - 0.000036) < 1e-12)
        var priced = rows[0]
        priced.agentKey = "codex"
        priced.agentName = "Codex"
        priced.model = "gpt-5.5"
        priced.inputTokens = 1_000_000
        priced.outputTokens = 1_000_000
        priced.cacheReadTokens = 1_000_000
        priced.cacheWriteTokens = 1_000_000
        let pricedSnapshot = CloudSnapshotAdapter.snapshot(rows: [priced, priced])
        precondition(abs(pricedSnapshot.totals.cost - 40.5) < 1e-9)
        precondition(pricedSnapshot.daily[0].cost == pricedSnapshot.totals.cost)
        precondition(pricedSnapshot.projects[0].cost == pricedSnapshot.totals.cost)
        priced.agentName = "Claude Code"
        priced.model = "claude-sonnet"
        precondition(abs(CloudSnapshotAdapter.snapshot(rows: [priced]).totals.cost - 22.05) < 1e-9)
        precondition(result.daily[0].totalTokens == 36)
        precondition(result.daily[0].tools["TeleAgent"] == 36)
        precondition(result.tools[0].tokens == 36 && result.models[0].tokens == 36)
        precondition(result.projects[0].tokens == 36)
        precondition(result.agentWork[0].bucket(hour: 9).totalTokens == 36)
        precondition(result.agentWork[0].activeHours == 1)
        precondition(result.agentWork[0].unbucketedTokens == 0)
        precondition(result.rhythms[0].totalTokens == 36)
        precondition(result.agentWork[0].cacheHitRate == nil) // No invented coverage.
        var sameAgentModel = rows[0]
        sameAgentModel.model = "another-model"
        var codex = rows[0]
        codex.agentKey = "codex"
        codex.agentName = "Codex"
        var previousDay = rows[0]
        previousDay.localDate = "2026-10-06"
        var sameNameDevice = second
        sameNameDevice.deviceName = rows[0].deviceName
        let devices = CloudSnapshotAdapter.deviceSources(rows: [rows[0], rows[0], sameAgentModel, codex, previousDay, sameNameDevice], date: "2026-10-07")
        precondition(devices.count == 2) // Device identity, never display name, defines a computer.
        precondition(devices[0].tokens == 54 && devices[1].tokens == 18)
        precondition(devices[0].agents.count == 2 && devices[0].agents[0].tokens == 36)
        precondition(devices[0].agents[0].name == "TeleAgent")
        precondition(devices.reduce(0) { $0 + $1.tokens } == 72)
        precondition(CloudSnapshotAdapter.deviceSources(rows: rows, date: "2026-10-08").isEmpty)
        var antigravity = second
        antigravity.agentKey = "antigravity"
        antigravity.agentName = "antigravity"
        var extraModel = antigravity
        extraModel.model = "gemini"
        let windows = CloudSnapshotAdapter.deviceSources(rows: [antigravity, extraModel, antigravity], date: "2026-10-07")
        precondition(windows.count == 1 && windows[0].osFamily == "windows")
        precondition(windows[0].agents[0].name == "Antigravity" && windows[0].agents[0].tokens == 36)
        antigravity.localDate = "2026-10-06"
        let fresh = CloudSourceStatus(device_id: second.deviceID, agent_key: "antigravity", state: "ok", files: 1, records: 1, last_succeeded_at: "2026-10-07T01:00:00.123Z")
        precondition(CloudSnapshotAdapter.deviceSources(rows: [antigravity], date: "2026-10-07", statuses: [fresh])[0].agents[0].tokens == 0)
        precondition(CloudSnapshotAdapter.deviceSources(rows: [antigravity], date: "2026-10-07")[0].agents[0].tokens == nil)
        var failed = fresh
        failed.state = "error"
        precondition(CloudSnapshotAdapter.deviceSources(rows: [antigravity], date: "2026-10-07", statuses: [failed])[0].agents[0].tokens == nil)
        rows[0].hourlyUsage = nil
        let legacy = CloudSnapshotAdapter.snapshot(rows: [rows[0]])
        precondition(legacy.totals.tokens == 18 && legacy.agentWork[0].unbucketedTokens == 18)
        precondition(legacy.rhythms.isEmpty)
        precondition(CloudSnapshotAdapter.snapshot(rows: []).daily.isEmpty)
        URLProtocol.registerClass(CloudHTTPFixture.self)
        let suite = "TokenStep.CloudFixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let passwords = FixturePasswordStorage()
        let store = SupabaseCloudStore(defaults: defaults, passwordStorage: passwords)
        store.projectURL = "https://fixture.invalid"
        store.publishableKey = "fixture-publishable"
        store.email = "fixture@example.invalid"
        store.password = "fixture-password-secret"
        var applied = 0
        store.onSnapshot = { _ in applied += 1 }
        store.signIn()
        for _ in 0..<500 where store.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(store.isAuthenticated && store.hasLoaded && applied == 1)
        precondition(store.sourceStatuses.count == 1 && store.sourceStatuses[0].device_id == second.deviceID)
        precondition(LifecycleLogger.lines.contains { $0.contains("cloud_snapshot_applied rows=0") })
        let restored = SupabaseCloudStore(defaults: defaults, passwordStorage: passwords)
        restored.restoreLogin()
        for _ in 0..<500 where restored.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(restored.isAuthenticated && restored.hasLoaded && restored.password.isEmpty)
        precondition(defaults.string(forKey: "TokenStep.Supabase.Password") == nil)
        CloudHTTPFixture.reject = true
        store.refresh()
        for _ in 0..<500 where store.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(store.errorMessage != nil && store.hasLoaded && applied == 1)
        precondition(!passwords.values.isEmpty) // Temporary cloud failure must keep automatic login.
        let otherDefaults = UserDefaults(suiteName: "TokenStep.CloudOther.\(UUID().uuidString)")!
        otherDefaults.set("https://other.invalid", forKey: "TokenStep.Supabase.URL")
        otherDefaults.set("fixture@example.invalid", forKey: "TokenStep.Supabase.Email")
        let otherProject = SupabaseCloudStore(defaults: otherDefaults, passwordStorage: passwords)
        otherProject.restoreLogin()
        precondition(!otherProject.isLoading && !otherProject.isAuthenticated)
        precondition(LifecycleLogger.lines.contains { $0.contains("cloud_refresh_failed") })
        store.signOut()
        precondition(!store.isAuthenticated && !store.hasLoaded && store.sourceStatuses.isEmpty)
        precondition(passwords.values.isEmpty)
        let signedOut = SupabaseCloudStore(defaults: defaults, passwordStorage: passwords)
        signedOut.restoreLogin()
        precondition(!signedOut.isLoading && !signedOut.isAuthenticated)
        let logs = LifecycleLogger.lines.joined(separator: "\n")
        for secret in ["fixture-password-secret", "fixture-access-secret", "fixture-refresh-secret", "fixture@example.invalid", "fixture-publishable"] {
            precondition(!logs.contains(secret))
        }
        print("cloud_snapshot_ok: multi-device, dedup, daily, model, project, TeleAgent hourly, legacy compatibility")
        print("cloud_read_logs_ok: auth, HTTP, apply, rejection, sign-out, credential redaction")
        let manualState = FileManager.default.temporaryDirectory.appendingPathComponent("tokenstep-manual-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: manualState, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: manualState) }
        let fakeAgent = manualState.appendingPathComponent("fake-agent")
        let agentScript = """
        #!/bin/sh
        if [ -f "$3/upload-fail" ]; then echo 'collection_ok at=fixture'; echo 'credential_read_ok at=fixture'; echo 'upload_started at=fixture'; exit 9; fi
        if [ -f "$3/fail" ]; then exit 9; fi
        if [ -f "$3/never" ]; then echo 'cycle_skipped already_running'; exit 0; fi
        if [ ! -f "$3/started" ]; then touch "$3/started"; echo 'cycle_skipped already_running'; exit 0; fi
        echo 'cycle_ok at=fixture'
        """
        try Data(agentScript.utf8).write(to: fakeAgent)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeAgent.path)
        try ManualUsageRefreshService.run(executable: fakeAgent, state: manualState, endpoint: "https://fixture.invalid/upload", timeout: 5)
        try Data().write(to: manualState.appendingPathComponent("fail"))
        do {
            try ManualUsageRefreshService.run(executable: fakeAgent, state: manualState, endpoint: "https://fixture.invalid/upload")
            preconditionFailure("failed agent must not be reported as refreshed")
        } catch ManualUsageRefreshService.RefreshError.agentFailed {}
        try FileManager.default.removeItem(at: manualState.appendingPathComponent("fail"))
        try Data().write(to: manualState.appendingPathComponent("upload-fail"))
        do {
            try ManualUsageRefreshService.run(executable: fakeAgent, state: manualState, endpoint: "https://fixture.invalid/upload")
            preconditionFailure("upload failure must identify successful collection")
        } catch ManualUsageRefreshService.RefreshError.uploadFailed {}
        try FileManager.default.removeItem(at: manualState.appendingPathComponent("upload-fail"))
        try Data().write(to: manualState.appendingPathComponent("never"))
        do {
            try ManualUsageRefreshService.run(executable: fakeAgent, state: manualState, endpoint: "https://fixture.invalid/upload", timeout: 0.2)
            preconditionFailure("busy agent must time out")
        } catch ManualUsageRefreshService.RefreshError.timedOut {}
        print("manual_refresh_ok: waits for busy collector, requires completion, rejects failure, bounded timeout")
        if ProcessInfo.processInfo.environment["TOKENSTEP_VERIFY_LIVE_REFRESH"] == "1" {
            try await ManualUsageRefreshService.collectAndUpload(projectURL: "https://hdizeqfyrdfbqohrnuzt.supabase.co")
            print("live_manual_refresh_ok: installed agent completed a new collection and acknowledged upload")
        }
    }
}

enum LifecycleLogger {
    static var lines: [String] = []
    static func log(_ message: String) { lines.append(message) }
}

final class CloudHTTPFixture: URLProtocol {
    static var reject = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let auth = request.url?.path.contains("/auth/") == true
        let statusBody = """
        [{"device_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","agent_key":"antigravity","state":"ok","files":1,"records":1,"last_succeeded_at":"2026-10-07T01:00:00Z"}]
        """
        let body = auth ? "{\"access_token\":\"fixture-access-secret\",\"refresh_token\":\"fixture-refresh-secret\",\"expires_in\":3600}" : (request.url?.path.contains("source_sync_status") == true && URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "offset" })?.value == "0" ? statusBody : "[]")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reject ? 503 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class FixturePasswordStorage: CloudPasswordStorage {
    var values: [String: String] = [:]
    func read(account: String) -> String? { values[account] }
    func save(_ password: String, account: String) -> Bool { values[account] = password; return true }
    func delete(account: String) { values.removeValue(forKey: account) }
}
