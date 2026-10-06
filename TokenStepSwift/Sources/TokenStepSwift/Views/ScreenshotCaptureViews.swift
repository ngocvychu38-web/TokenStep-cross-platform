import SwiftUI

struct DashboardScreenshotView: View {
    @EnvironmentObject private var appState: AppState
    var section: AppSection

    var body: some View {
        ZStack {
            TokenStepBackdrop()

            VStack(alignment: .leading, spacing: 28) {
                captureHeader
                detailView
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 36)
        }
        .frame(width: 1120)
        .fixedSize(horizontal: false, vertical: true)
        .id(appState.appearanceID)
    }

    private var captureHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            TokenStepMark(size: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text("TokenStep")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text(L("每天一个亿"))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.tokenGreenDark)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 7) {
                Text(section.title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text("\(L("更新")) \(TokenStepFormat.generatedTime(appState.snapshot.generatedAt))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch section {
        case .today:
            TodayView()
        case .history:
            HistoryView(historyLimit: 30)
        case .privacy:
            PrivacyView()
        }
    }
}
