#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
SWIFT_DIR = ROOT_DIR / "TokenStepSwift/Sources/TokenStepSwift"


def read(relative_path: str) -> str:
    return (SWIFT_DIR / relative_path).read_text(encoding="utf-8")


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> int:
    failures: list[str] = []

    formatters = read("Support/Formatters.swift")
    components = read("Views/Components.swift")
    token_island = read("Views/TokenIslandView.swift")
    app = read("App/TokenStepApp.swift")
    app_state = read("Stores/AppState.swift")

    require(
        "language explicitLanguage: TokenStepLanguage? = nil" in formatters,
        "TokenStepFormat.tokens must accept an explicit language.",
        failures,
    )
    require(
        'language == .zhHant ? "萬" : "万"' in formatters,
        "Token formatter must keep separate Simplified and Traditional ten-thousand units.",
        failures,
    )
    require(
        'if language == .en' in formatters and 'return "\\(trim(Double(value) / 1_000_000, digits: digits))M"' in formatters,
        "Token formatter must keep English compact M units.",
        failures,
    )

    require(
        "var appearanceID: String" in app_state and "settings.language.resolved.id" in app_state,
        "AppState must expose an appearanceID that includes resolved language.",
        failures,
    )

    for name, source in [
        ("StatusBarLabelView", components),
        ("TokenIslandRingView", token_island),
    ]:
        pattern = re.compile(rf"struct {name}: View \{{(?P<body>.*?)(?=^struct |\Z)", re.S | re.M)
        match = pattern.search(source)
        require(match is not None, f"{name} not found.", failures)
        if not match:
            continue
        body = match.group("body")
        require(
            "var language: TokenStepLanguage" in body,
            f"{name} must receive language as an explicit input.",
            failures,
        )
        require(
            "TokenStepFormat.tokens(tokens, compact: true, language: language)" in body,
            f"{name} must format the menu text with the explicit language.",
            failures,
        )
        require(
            "language.resolved.id" in body,
            f"{name} must include language in its SwiftUI identity.",
            failures,
        )

    require(
        "language: appState.settings.language" in app,
        "Menu bar status label must pass appState.settings.language.",
        failures,
    )
    require(
        "language: appState.settings.language" in token_island,
        "Token Island ring must pass appState.settings.language.",
        failures,
    )
    require(
        ".id(appState.appearanceID)" in app
        and token_island.count(".id(appState.appearanceID)") >= 2
        and ".id(appState.appearanceID)" in read("Views/PopoverPanelView.swift")
        and ".id(appState.appearanceID)" in read("Views/SettingsView.swift"),
        "Top-level views must refresh with appearanceID, not theme only.",
        failures,
    )

    if failures:
        for failure in failures:
            print(f"language-refresh-check: {failure}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
