import SwiftUI

/// 公开 Token Rank 多人榜：账号与名称来自公开榜单，客户端按 Token 倒序展示。
struct TodayMemberLeaderboardCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 15) {
                header
                currentAccount
                memberRows
                footer
            }
        }
        .onAppear {
            appState.refreshTokenRank()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Agent 消耗榜"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(L("按 Token 消耗排序"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.isRefreshingTokenRank {
                ProgressView().controlSize(.small)
            } else if appState.tokenRank != nil {
                Text(LFormat("%d 人", displayedEntries.count))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var currentAccount: some View {
        HStack(spacing: 13) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.tokenGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.tokenGreen.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(L("当前账号"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(displayIdentity.name)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Text(displayIdentity.id == TokenRankLocalDisplay.localUserID
                        ? L("本机账号")
                        : "ID \(displayIdentity.id)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(L("我的今日 Token"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(TokenStepFormat.tokens(currentAccountTokens))
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                        .monospacedDigit()
                    Text(currentUsesLocalTokens
                        ? LFormat("本机统计 · 今日排名 #%d", currentDisplayEntry.rank)
                        : LFormat("今日排名 #%d", currentDisplayEntry.rank))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.tokenGreenDark)
                }
        }
        .padding(14)
        .background(Color.tokenGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var memberRows: some View {
        if !displayedEntries.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(Array(displayedEntries.enumerated()), id: \.element.id) { index, entry in
                    memberRow(entry)
                    if index < displayedEntries.count - 1 {
                        Divider().opacity(0.55)
                    }
                }
            }
            .padding(.horizontal, 4)
        } else if let error = appState.tokenRankError {
            Text(error)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    private func memberRow(_ entry: TokenRankEntry) -> some View {
        let isCurrent = entry.userID == displayIdentity.id
        return HStack(spacing: 13) {
            Text("#\(entry.rank)")
                .font(.callout.weight(.heavy))
                .foregroundStyle(entry.rank <= 3 ? Color.tokenGreenDark : Color.secondary)
                .monospacedDigit()
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(entry.name)
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                        .lineLimit(1)
                    if isCurrent {
                        Text(L("我"))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.tokenGreenDark)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.tokenGreen.opacity(0.15), in: Capsule())
                    }
                }
                Text(entry.userID == TokenRankLocalDisplay.localUserID ? L("本机账号") : "ID \(entry.userID)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(TokenStepFormat.tokens(entry.totalTokens))
                .font(.callout.weight(.heavy))
                .foregroundStyle(isCurrent ? Color.tokenGreenDark : Color.tokenInk)
                .monospacedDigit()

            if !isCurrent, entry.userID > 0 {
                Button(L("设为当前账号")) {
                    appState.selectTokenRankAccount(entry)
                }
                .buttonStyle(.borderless)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.tokenGreenDark)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(isCurrent ? Color.tokenGreen.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var footer: some View {
        HStack {
            if let leaderboard = appState.tokenRank {
                Text(footerCountText(leaderboard))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.openTokenRankLeaderboardPage()
            } label: {
                Label(L("打开榜单"), systemImage: "arrow.up.right")
                    .font(.caption.weight(.heavy))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.tokenGreenDark)
        }
    }

    private var displayBundle: (identity: AgentWorkRankIdentity, entries: [TokenRankEntry]) {
        TokenRankLocalDisplay.rankedEntries(
            leaderboard: appState.tokenRank,
            explicitIdentity: appState.agentWorkRankIdentity,
            localTokens: appState.today.totalTokens
        )
    }

    private var displayIdentity: AgentWorkRankIdentity {
        displayBundle.identity
    }

    private var currentDisplayEntry: TokenRankEntry {
        displayBundle.entries.first(where: { $0.userID == displayIdentity.id })
            ?? TokenRankEntry(
                rank: displayBundle.entries.count,
                userID: displayIdentity.id,
                name: displayIdentity.name,
                avatarURL: nil,
                totalTokens: appState.today.totalTokens,
                callCount: 0,
                sessionCount: 0,
                clients: [:],
                models: [:]
            )
    }

    private var currentAccountTokens: Int {
        currentDisplayEntry.totalTokens
    }

    private var currentUsesLocalTokens: Bool {
        appState.tokenRank?.entry(matching: displayIdentity.id) == nil
    }

    private var displayedEntries: [TokenRankEntry] {
        displayBundle.entries
    }

    private func footerCountText(_ leaderboard: TokenRankLeaderboard) -> String {
        if appState.agentWorkRankIdentity == nil {
            return leaderboard.entries.count < leaderboard.totalRankedUsers
                ? LFormat(
                    "本机 1 人 + 公开 %d / %d 人（接口上限）",
                    leaderboard.entries.count,
                    leaderboard.totalRankedUsers
                )
                : LFormat("本机榜单共 %d 人", displayedEntries.count)
        }
        return leaderboard.entries.count < leaderboard.totalRankedUsers
            ? LFormat(
                "已显示 %d / %d 人（公开接口上限）",
                leaderboard.entries.count,
                leaderboard.totalRankedUsers
            )
            : LFormat("共 %d 人", displayedEntries.count)
    }
}
