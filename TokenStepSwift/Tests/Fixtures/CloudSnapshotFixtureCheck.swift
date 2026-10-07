import Foundation

@main
struct CloudSnapshotFixtureCheck {
    @MainActor static func main() async throws {
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
