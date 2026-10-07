import AppKit
import SwiftUI

@main struct ScreenshotExportFixture {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "TokenStep.ScreenshotFixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = SupabaseCloudStore(defaults: defaults)
        let state = AppState(cloud: cloud, startServices: false)
        let baseJSON = """
        {"workspace_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","local_date":"2026-10-07","device_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","device_name":"Fixture computer","os_family":"windows","os_version":"11","architecture":"x86_64","agent_key":"codex","agent_name":"Codex","project_key":"p","project_name":"Long project name for screenshot coverage","model":"gpt-5.5","input_tokens":1000000,"output_tokens":100000,"cache_read_tokens":10000,"cache_write_tokens":0,"reasoning_tokens":0,"total_tokens":1110000,"record_count":1,"hourly_usage":[{"hour":9,"record_count":1,"tokens":{"input_tokens":1000000,"output_tokens":100000,"cache_read_tokens":10000,"cache_write_tokens":0,"reasoning_tokens":0,"total_tokens":1110000}}]}
        """
        let base = try JSONDecoder().decode(CloudUsageRow.self, from: Data(baseJSON.utf8))
        var rows: [CloudUsageRow] = []
        let calendar = ContributionWallCalendar.calendar
        for offset in 0..<35 {
            for agent in 0..<6 {
                var row = base
                row.localDate = DateFormatter.tokenStepDay.string(from: calendar.date(byAdding: .day, value: -offset, to: Date())!)
                row.agentKey = "agent-\(agent)"
                row.agentName = ["Codex", "Claude Code", "Antigravity", "TeleAgent", "Gemini CLI", "OpenCode"][agent]
                row.model = "model-\(agent)-long-name"
                row.projectKey = "project-\(agent)"
                row.projectName = "Project \(agent) with long screenshot name"
                rows.append(row)
            }
        }
        let snapshot = CloudSnapshotAdapter.snapshot(rows: rows)
        cloud.onSnapshot?(snapshot)
        let day = snapshot.daily.last!
        let yesterday = snapshot.daily[snapshot.daily.count - 2]
        let rhythm = snapshot.rhythms[snapshot.rhythms.count - 2]
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_SCREENSHOT_OUTPUT"] ?? "/tmp/tokenstep-screenshot-checks")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [TokenStepLanguage.zhHans, .en] {
            TokenStepLocalization.apply(language)
            func check<V: View>(_ view: V, _ name: String) throws {
                let image = try ScreenshotExporter.render(view.environmentObject(state).environment(\.colorScheme, .light))
                let png = try ScreenshotExporter.pngData(from: image)
                let jpg = try ScreenshotExporter.jpgData(from: image)
                let bitmap = NSBitmapImageRep(data: png)!
                let jpeg = NSBitmapImageRep(data: jpg)!
                precondition(bitmap.pixelsWide == jpeg.pixelsWide && bitmap.pixelsHigh == jpeg.pixelsHigh)
                precondition(bitmap.pixelsHigh > 0 && bitmap.pixelsWide > 0)
                if name == "today" || name == "yesterday" {
                    precondition(image.size.height > 840) // Rich cards must grow beyond the old cap.
                }
                try png.write(to: directory.appendingPathComponent("\(language.rawValue)-\(name).png"))
                print("\(language.rawValue)-\(name): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
            }
            try check(ShareDailyCardView(mode: .today, day: day, previousDay: yesterday), "today")
            try check(ShareDailyCardView(mode: .yesterday, day: yesterday, previousDay: nil), "yesterday")
            try check(ShareRhythmCardView(day: yesterday, rhythm: rhythm, previousDay: nil), "yesterday-rhythm")
            try check(PopoverPanelView(), "popover")
            for section in AppSection.allCases {
                try check(DashboardScreenshotView(section: section), "dashboard-\(section.rawValue)")
            }
            try check(SettingsView(captureMode: true).frame(width: 900), "settings")
        }
        print("screenshot_export_ok: all export views, Chinese/English, PNG/JPEG dimensions")
    }
}
