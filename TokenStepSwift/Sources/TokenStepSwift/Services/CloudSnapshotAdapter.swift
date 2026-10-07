import Foundation

/// All usage surfaces cross this single seam. Never reads local collector files.
enum CloudSnapshotAdapter {
    static func deviceSources(rows: [CloudUsageRow], date: String, statuses: [CloudSourceStatus] = []) -> [CloudDeviceUsage] {
        let unique = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values
        let devices = Dictionary(grouping: unique, by: \.deviceID)
        return devices.compactMap { deviceID, rows -> CloudDeviceUsage? in
            let todayRows = rows.filter { $0.localDate == date && $0.totalTokens > 0 }
            guard !todayRows.isEmpty || rows.contains(where: { sourceDay($0.lastSeenAt) == date })
                || statuses.contains(where: { $0.device_id == deviceID && $0.state == "ok" && sourceDay($0.last_succeeded_at) == date }) else { return nil }
            let metadata = rows.sorted { $0.id < $1.id }[0]
            let byAgent = Dictionary(grouping: rows, by: \.agentKey)
            var agents: [CloudAgentUsage] = []
            for (key, agentRows) in byAgent {
                let name = key.lowercased() == "antigravity" ? "Antigravity" : agentRows.sorted { $0.id < $1.id }[0].agentName
                let todayAgentRows = agentRows.filter { $0.localDate == date }
                let status = statuses.first { $0.device_id == deviceID && $0.agent_key == key }
                let capturedToday = status?.state == "ok" && sourceDay(status?.last_succeeded_at) == date
                let tokens: Int? = !todayAgentRows.isEmpty || capturedToday
                    ? todayAgentRows.reduce(0) { $0 + $1.totalTokens } : nil
                agents.append(CloudAgentUsage(id: key, name: name, tokens: tokens))
            }
            agents.sort { $0.tokens == $1.tokens ? $0.id < $1.id : ($0.tokens ?? 0) > ($1.tokens ?? 0) }
            return CloudDeviceUsage(id: deviceID, name: metadata.deviceName, osFamily: metadata.osFamily,
                tokens: todayRows.reduce(0) { $0 + $1.totalTokens }, agents: agents)
        }.sorted {
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func sourceDay(_ timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        return date.map { DateFormatter.tokenStepDay.string(from: $0) }
    }

    static func snapshot(rows: [CloudUsageRow], statuses: [CloudSourceStatus] = []) -> UsageSnapshot {
        let rows = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values
        let all = Array(rows)
        let total = all.reduce(0) { $0 + $1.totalTokens }
        let byDay = Dictionary(grouping: all, by: \.localDate)
        let daily = byDay.keys.sorted().map { day in
            let dayRows = byDay[day] ?? []
            return DailyUsage(date: day, tools: totals(dayRows, by: \.agentName), models: totals(dayRows, by: \.model),
                totalTokens: dayRows.reduce(0) { $0 + $1.totalTokens }, cost: dayRows.reduce(0) { $0 + estimatedCost($1) }, projects: projects(dayRows))
        }
        let work = byDay.keys.sorted().map { day -> DailyAgentWork in
            let dayRows = byDay[day] ?? []
            let sources = totals(dayRows, by: \.agentName).sorted { $0.key < $1.key }.map {
                AgentWorkSource(source: $0.key, tokens: $0.value, modelRequestCount: 0, toolCallCount: 0)
            }
            let hours = (0..<24).map { hour -> AgentWorkHourBucket in
                let hourlyByAgent = Dictionary(grouping: dayRows.flatMap { row in
                    (row.hourlyUsage ?? []).filter { $0.hour == hour }.map { (row.agentName, $0.tokens) }
                }, by: { $0.0 })
                let hourly = hourlyByAgent.keys.sorted().map { agent -> AgentWorkHourlySource in
                    let counts = (hourlyByAgent[agent] ?? []).map { $0.1 }
                    return AgentWorkHourlySource(source: agent, tokens: counts.reduce(0) { $0 + $1.total_tokens },
                        inputTokens: counts.reduce(0) { $0 + $1.input_tokens + $1.cache_read_tokens },
                        cachedInputTokens: counts.reduce(0) { $0 + $1.cache_read_tokens },
                        outputTokens: counts.reduce(0) { $0 + $1.output_tokens }, cacheCoverageComplete: false)
                }
                return AgentWorkHourBucket(hour: hour, sources: hourly)
            }
            return DailyAgentWork(date: day, totalTokens: dayRows.reduce(0) { $0 + $1.totalTokens },
                activeHours: hours.filter { $0.totalTokens > 0 }.count, modelRequestCount: 0, toolCallCount: 0,
                sources: sources, inputTokens: dayRows.reduce(0) { $0 + $1.inputTokens + $1.cacheReadTokens },
                cachedInputTokens: dayRows.reduce(0) { $0 + $1.cacheReadTokens },
                outputTokens: dayRows.reduce(0) { $0 + $1.outputTokens }, cacheCoverageComplete: false, hourlyBuckets: hours)
        }
        let rhythms = work.filter { $0.hourlyBuckets.contains { $0.totalTokens > 0 } }.map { day -> DailyRhythm in
            let active = day.hourlyBuckets.filter { $0.totalTokens > 0 }
            let peak = active.max { $0.totalTokens < $1.totalTokens }
            let peakHour = peak?.hour ?? 0
            let tag: RhythmTag = peakHour < 6 ? .nightAgent : peakHour < 12 ? .morningPlanner : peakHour < 18 ? .afternoonBurst : .eveningSprint
            return DailyRhythm(date: day.date, buckets: day.hourlyBuckets.map { HourlyTokenBucket(hour: $0.hour, tokens: $0.totalTokens) },
                totalTokens: day.hourlyBuckets.reduce(0) { $0 + $1.totalTokens }, peakHour: peak?.hour,
                peakTokens: peak?.totalTokens ?? 0, activeHours: active.count, firstActiveHour: active.first?.hour,
                lastActiveHour: active.last?.hour, primaryTag: tag, companionTag: .steadyCruise)
        }
        var sources: [String: SourceInfo] = [:]
        for status in statuses {
            let name = all.first { $0.agentKey == status.agent_key }?.agentName ?? status.agent_key
            var info = sources[name] ?? SourceInfo()
            if info.status == nil || status.state.contains("failed") || info.status == "missing" { info.status = status.state }
            info.files = (info.files ?? 0) + status.files
            info.records = (info.records ?? 0) + status.records
            info.strategy = "supabase_rust"
            sources[name] = info
        }
        return UsageSnapshot(generatedAt: all.compactMap(\.lastSeenAt).max(), timezone: "Asia/Shanghai",
            totals: UsageTotals(tokens: total, cost: all.reduce(0) { $0 + estimatedCost($1) }, activeDays: daily.filter { $0.totalTokens > 0 }.count),
            daily: daily, rhythms: rhythms, agentWork: work,
            tools: totals(all, by: \.agentName).sorted { $0.value > $1.value }.map {
                ToolUsage(tool: $0.key, tokens: $0.value, percent: total > 0 ? Double($0.value) * 100 / Double(total) : 0)
            }, models: Dictionary(grouping: all, by: { $0.agentName + "\u{0}" + $0.model }).values.map { group in
                let count = group.reduce(0) { $0 + $1.totalTokens }
                return ModelUsage(model: group[0].model, tool: group[0].agentName, tokens: count,
                    percent: total > 0 ? Double(count) * 100 / Double(total) : 0)
            }.sorted { $0.tokens > $1.tokens }, sources: sources, projects: projects(all))
    }

    private static func estimatedCost(_ row: CloudUsageRow) -> Double {
        // Cloud input excludes cache buckets; legacy pricing expects inclusive input.
        TokenCostEstimator.estimate(usage: .init(
            inputTokens: row.inputTokens + row.cacheReadTokens + row.cacheWriteTokens,
            outputTokens: row.outputTokens, cacheCreationInputTokens: row.cacheWriteTokens,
            cacheReadInputTokens: row.cacheReadTokens, totalTokens: row.totalTokens),
            tool: row.agentName, model: row.model)
    }

    private static func totals(_ rows: [CloudUsageRow], by key: KeyPath<CloudUsageRow, String>) -> [String: Int] {
        rows.reduce(into: [:]) { $0[$1[keyPath: key], default: 0] += $1.totalTokens }
    }

    private static func projects(_ rows: [CloudUsageRow]) -> [ProjectUsage] {
        Dictionary(grouping: rows, by: \.projectName).map { name, rows in
            ProjectUsage(name: name, tokens: rows.reduce(0) { $0 + $1.totalTokens }, cost: rows.reduce(0) { $0 + estimatedCost($1) },
                tools: totals(rows, by: \.agentName), models: totals(rows, by: \.model))
        }.sorted { $0.tokens > $1.tokens }
    }
}
