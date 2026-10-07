import Foundation

@main
struct CloudSnapshotFixtureCheck {
    static func main() throws {
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
        precondition(result.daily[0].totalTokens == 36)
        precondition(result.daily[0].tools["TeleAgent"] == 36)
        precondition(result.tools[0].tokens == 36 && result.models[0].tokens == 36)
        precondition(result.projects[0].tokens == 36)
        precondition(result.agentWork[0].bucket(hour: 9).totalTokens == 36)
        precondition(result.agentWork[0].activeHours == 1)
        precondition(result.agentWork[0].unbucketedTokens == 0)
        precondition(result.rhythms[0].totalTokens == 36)
        precondition(result.agentWork[0].cacheHitRate == nil) // No invented coverage.
        rows[0].hourlyUsage = nil
        let legacy = CloudSnapshotAdapter.snapshot(rows: [rows[0]])
        precondition(legacy.totals.tokens == 18 && legacy.agentWork[0].unbucketedTokens == 18)
        precondition(legacy.rhythms.isEmpty)
        precondition(CloudSnapshotAdapter.snapshot(rows: []).daily.isEmpty)
        print("cloud_snapshot_ok: multi-device, dedup, daily, model, project, TeleAgent hourly, legacy compatibility")
    }
}
