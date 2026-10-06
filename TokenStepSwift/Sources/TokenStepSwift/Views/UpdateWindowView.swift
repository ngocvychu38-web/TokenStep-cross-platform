import SwiftUI

struct UpdateWindowView: View {
    @EnvironmentObject private var appState: AppState
    var update: AvailableUpdate

    var body: some View {
        ZStack {
            TokenStepBackdrop()

            VStack(alignment: .leading, spacing: 22) {
                header
                releaseNotes
                trustPanel
                progressPanel
                footer
            }
            .padding(28)
        }
        .frame(width: 560, height: 500)
        .id(appState.appearanceID)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            TokenStepMark(size: 60)

            VStack(alignment: .leading, spacing: 7) {
                Text(LFormat("TokenStep %@ 可用", update.version))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.tokenInk)
                Text(L("安装完成后会自动重启到新版本"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var releaseNotes: some View {
        TokenCard {
            VStack(alignment: .leading, spacing: 13) {
                Text(L("更新内容"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)

                let notes = update.noteLines.isEmpty ? defaultNotes : update.noteLines
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.tokenGreen)
                            .padding(.top, 2)
                        Text(note)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.tokenInk.opacity(0.78))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trustPanel: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.tokenGreenDark)
                .frame(width: 34, height: 34)
                .background(Color.tokenMint.opacity(0.28), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(L("自动安装到 Applications"))
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(L("下载后会验证 DMG 中的 App，并替换旧版本"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(update.formattedSize)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.tokenInk.opacity(0.65))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.tokenTrack.opacity(0.38), in: Capsule())
        }
        .padding(13)
        .background(Color.tokenSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.055)))
    }

    @ViewBuilder
    private var progressPanel: some View {
        if appState.isDownloadingUpdate {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appState.updateInstallStatus)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(TokenStepFormat.percent(appState.updateDownloadProgress * 100))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.tokenInk.opacity(0.7))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.tokenTrack)
                        Capsule()
                            .fill(Color.tokenGreen)
                            .frame(width: proxy.size.width * min(max(appState.updateDownloadProgress, 0), 1))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                appState.skipAvailableUpdate()
                UpdateWindowPresenter.shared.close()
            } label: {
                Text(L("跳过此版本"))
                    .font(.callout.weight(.bold))
                    .frame(width: 100, height: 38)
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
            .disabled(appState.isDownloadingUpdate)

            Spacer()

            Button {
                UpdateWindowPresenter.shared.close()
            } label: {
                Text(L("稍后"))
                    .font(.callout.weight(.bold))
                    .frame(width: 76, height: 38)
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
            .disabled(appState.isDownloadingUpdate)

            Button {
                appState.installAvailableUpdate()
            } label: {
                Text(appState.isDownloadingUpdate ? L("安装中") : L("安装并重启"))
                    .font(.callout.weight(.heavy))
                    .frame(width: 126, height: 38)
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .disabled(appState.isDownloadingUpdate)
        }
    }

    private var defaultNotes: [String] {
        [
            L("优化 Codex 历史数据读取"),
            L("降低后台刷新 CPU 占用"),
            L("提升菜单栏同步稳定性")
        ]
    }
}
