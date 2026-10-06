import AppKit
import SwiftUI

struct PopoverFooterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(L("本地统计"), systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.settings.refreshIntervalSeconds == 0 ? L("手动刷新") : LFormat("刷新 %@", TokenStepFormat.intervalLabel(appState.settings.refreshIntervalSeconds)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    MainWindowPresenter.shared.show(appState: appState)
                } label: {
                    Label(L("打开仪表盘"), systemImage: "arrow.up.right")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.tokenGreen, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .shadow(color: Color.tokenGreenDark.opacity(0.14), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .help(L("打开仪表盘"))

                PopoverActionButton(title: L("刷新"), symbol: "arrow.clockwise") {
                    appState.refresh()
                }
                .disabled(appState.isRefreshing)

                PopoverActionButton(title: L("设置"), symbol: "gearshape") {
                    SettingsWindowPresenter.shared.show(appState: appState)
                }

                PopoverActionButton(title: L("退出"), symbol: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

private struct PopoverActionButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .heavy))
                    .frame(height: 20)
                Text(title)
                    .font(.caption2.weight(.heavy))
            }
            .foregroundStyle(Color.tokenInk.opacity(0.78))
            .frame(width: 54, height: 54)
            .background(Color.tokenSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.black.opacity(0.055)))
            .shadow(color: Color.black.opacity(0.045), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
