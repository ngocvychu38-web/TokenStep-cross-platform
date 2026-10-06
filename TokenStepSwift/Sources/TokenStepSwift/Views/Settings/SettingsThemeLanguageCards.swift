import SwiftUI

struct SettingsThemeCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("主题色"), symbol: "paintpalette.fill") {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("菜单栏、圆环、活动墙和按钮会一起跟随主题变化。"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    ForEach(TokenStepTheme.allCases) { theme in
                        ThemeSwatchButton(
                            theme: theme,
                            selected: appState.settings.theme == theme
                        ) {
                            appState.setTheme(theme)
                        }
                    }
                }

                StatusLine(
                    symbol: "sparkles",
                    title: L("当前主题"),
                    value: appState.settings.theme.title,
                    tint: .tokenGreen
                )

                Spacer(minLength: 0)
            }
        }
    }
}

struct SettingsLanguageCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: L("语言"), symbol: "globe.asia.australia.fill", height: 268) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("选择 TokenStep 的显示语言"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(TokenStepLanguage.allCases) { language in
                        LanguageOptionButton(
                            language: language,
                            selected: appState.settings.language == language
                        ) {
                            appState.setLanguage(language)
                        }
                    }
                }

                StatusLine(
                    symbol: "character.bubble.fill",
                    title: L("当前语言"),
                    value: appState.settings.language.title,
                    tint: .tokenGreen
                )
            }
        }
    }
}
