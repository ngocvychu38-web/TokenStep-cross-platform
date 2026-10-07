import SwiftUI

struct PopoverTodayRingCard: View {
    @EnvironmentObject private var appState: AppState

    private var hasNoData: Bool {
        appState.collectionFreshness.kind == .neverSucceeded
    }

    var body: some View {
        let lap = appState.todayLap
        return TokenCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("今日 Token 消耗"))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Spacer()
                    Text(appState.today.date)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 20) {
                    ZStack {
                        ProgressRingView(progress: lap.currentLapProgress, lineWidth: 16, color: lap.color)
                        VStack(spacing: 3) {
                            if hasNoData {
                                // 从未成功：显示"暂无数据"，不显示 0（G-V1）。
                                Text(L("暂无数据"))
                                    .font(.callout.weight(.heavy))
                                    .foregroundStyle(.secondary)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                            } else {
                                Text(TokenStepFormat.tokens(appState.today.totalTokens))
                                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.tokenInk)
                                    .minimumScaleFactor(0.52)
                                    .lineLimit(1)
                            }
                            Text(LFormat("/ %@ 每圈", TokenStepFormat.tokens(appState.settings.dailyGoalTokens, compact: true)))
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 122)
                    }
                    .frame(width: 148, height: 148)

                    VStack(alignment: .leading, spacing: 11) {
                        Text(lap.lapTitle)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        Text(lap.lapPercentText)
                            .font(.system(size: 43, weight: .heavy, design: .rounded))
                            .foregroundStyle(lap.color)
                            .monospacedDigit()
                        Text(lap.completedLapsText)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            MetricPill(
                                label: L("消耗金额（估算）"),
                                value: hasNoData || appState.usesCloudData ? "—" : TokenStepFormat.money(appState.today.cost)
                            )
                            .help(L("按 API 列表价估算，不代表订阅或实际账单。"))
                            MetricPill(label: L("活跃"), value: localizedDays(appState.snapshot.totals.activeDays))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !appState.todayDeviceSources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("今日来源"))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.secondary)
                        ForEach(appState.todayDeviceSources) { device in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: device.osFamily == "windows" ? "pc" : "laptopcomputer")
                                        .foregroundStyle(.secondary)
                                    Text(device.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(TokenStepFormat.tokens(device.tokens, compact: true))
                                        .monospacedDigit()
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.tokenInk.opacity(0.82))
                                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                                    ForEach(device.agents) { agent in
                                        TodaySourceMetric(name: agent.name, tokens: agent.tokens)
                                    }
                                }
                                .padding(.leading, 20)
                            }
                            .padding(10)
                            .background(Color.tokenGreen.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.top, 1)
                }

                // G-B1：今日路线（Popover 紧凑版）。
                if let projects = appState.today.projects, !projects.isEmpty {
                    let total = max(1, projects.reduce(0) { $0 + $1.tokens })
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("今日路线"))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.secondary)
                        ForEach(projects.prefix(3)) { project in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tokenGreen.opacity(0.75))
                                    .frame(width: 5, height: 5)
                                Text(TokenStepProject.displayName(project.name))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.tokenInk.opacity(0.78))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(
                                    "\(TokenStepFormat.tokens(project.tokens, compact: true)) · \(TokenStepFormat.percent(Double(project.tokens) * 100 / Double(total)))"
                                )
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }
        }
    }

    private func localizedDays(_ count: Int) -> String {
        TokenStepLocalization.language == .en ? "\(count)d" : "\(count) 天"
    }

}

private struct TodaySourceMetric: View {
    var name: String
    var tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tokenToolColor(name))
                    .frame(width: 6, height: 6)
                Text(displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(TokenStepFormat.tokens(tokens, compact: true))
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.82))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayName: String {
        name == "Claude Code" ? "Claude" : name
    }
}
