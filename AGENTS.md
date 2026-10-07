# TokenStep project context

This file is the persistent project briefing for Codex and other coding agents. Read it before changing the repository. It captures the architecture and constraints established from the source snapshot downloaded on 2026-08-14.

## Cross-platform architecture (active development branch)

### Current authority (2026-10-07)

This section overrides the legacy local-first descriptions below. All production usage pages, popover and share cards now consume one authenticated Supabase store through `CloudSnapshotAdapter` and `AppState`; there is no local usage fallback. Legacy Swift collection is retained for reference/parity fixtures only. Cloud fields without authoritative equivalents (cost, tool-call counts, complete cache coverage) render unavailable.

Rust `cycle` owns local collection, durable outbox, upload and exclusive process locking. macOS LaunchAgent `com.tokenstep.collector` uses the stable executable under Application Support/TokenStep/agent/bin. Testing interval is 60 seconds; future production interval is 600 seconds. Keychain authorization for the installed binary is required. Read `docs/CLOUD_MIGRATION_VERIFICATION.md` before changing scheduling, cloud presentation or validating deployment. Original Swift Codex accounting features are not all proven equivalent in Rust.

Privacy: upload sanitized device/project/Agent/model metadata and daily/hourly token aggregates only. Raw logs, code, conversations, full paths and secrets stay local. Client login credentials remain process-memory only; relaunch requires login. Device upload credentials remain in OS credential storage.

`codex/rust-cross-platform` introduces the new authoritative collection and cloud contract:

- `rust/tokenstep-core`: cross-platform deep collection module. Its external seam is `SourceAdapter`; adapters return normalized `UsageFact` values and safe `SourceDiagnostic` metadata.
- `rust/tokenstep-agent`: macOS Intel/Windows x64 CLI for `collect`, `verify`, `doctor`, `enroll`, and `sync`.
- `UsageBucketV1`: cloud payload grouped by the joint dimensions day × Agent × model × project. Do not derive cloud payloads from `UsageSnapshot`, because its separate tool/model/project aggregates have lost those joint relationships.
- `supabase/`: Postgres migrations plus device-enrollment and ingestion Edge Functions. Collectors never receive a Supabase service-role key.
- `CloudDashboardView` / `SupabaseCloudService`: display-side Supabase Auth and RLS-protected `usage_dashboard` reads.
- `docs/CROSS_PLATFORM_ROLLOUT.md`: authoritative deployment and independent verification gates.

The previous Swift collector remains available during parity migration. New source logic should be implemented in Rust and verified with fixtures before the Swift implementation is retired.

Rust verification:

```bash
./script/verify_rust_collector.sh
./script/verify_cloud_assets.sh
cargo test --workspace
```

## Repository state

- Upstream: `https://github.com/Backtthefuture/TokenStep`
- This workspace was downloaded as a ZIP without upstream history. Local Git history now starts at backup commit `c556839`, pushed to private repository `ngocvychu38-web/TokenStep-cross-platform`; active branch is `codex/rust-cross-platform`.
- Product version in the current source and packaging scripts: `0.2.0`.
- License: MIT.
- Supported runtime: macOS 14 or newer. Production/release builds default to Apple Silicon (`arm64-apple-macos14.0`); `TOKENSTEP_ARCH=x86_64` produces a local Intel build.

## What the product does

TokenStep is a local-first native macOS menu-bar application that treats daily AI token usage like a fitness goal. The default goal is 100 million tokens per day; progress can run through multiple laps.

User-facing capabilities include:

- Menu-bar token count and progress ring, plus an optional notch-adjacent “Token Island”.
- Lightweight popover and a larger dashboard for today, history, statistics, agent/model/project breakdowns, and privacy information.
- The MenuBarExtra popover is vertically scrollable, uses 90% of the active screen's visible height, and widens adaptively up to 560 pt without exceeding 90% of screen width. Keep screenshot rendering vertically uncapped so share/capture output is not clipped.
- Configurable daily goal, history window, refresh interval, theme, language, launch-at-login, and display placement.
- Daily and hourly activity/rhythm views, 30-day trends, contribution wall, cache/input/output/tool-call metrics, and shareable PNG cards/screenshots.
- Agent Work source filters expose Codex, TeleAgent, Hermes, and Other separately; TeleAgent must not be folded into Other once its collector is enabled.
- Local list-price cost estimates. These are explicitly estimates, never billing data.
- Optional Codex weekly quota and Claude Code 5-hour/7-day quota views.
- Optional, explicit opt-in public token-rank display. Returned public members are sorted locally by Token descending; the dashboard renders every row returned by the API (no client-side limit) while the popover remains a five-row preview. Both show account ID/name/Token and highlight the current identity loaded from `~/.token-rank/client-state.json`, falling back to an explicit locally stored public user ID/name selected from the leaderboard. With neither identity, an in-memory-only local member uses the macOS account display name plus local today Token and is never uploaded. Browser cookies and website session tokens are never imported.
- Signed DMG update checking, download, verification, transactional install, rollback, and relaunch.
- Experimental local collectors for additional agents. Multi-device sync types and tests exist, but the production transport/UI remain gated until the server contract is ready.

## Architecture and main data flow

The production application is the SwiftUI implementation under `TokenStepSwift`. The older Python/PyObjC implementation under `TokenUsageMenuApp`, plus root `token_usage_monitor.py` and launchd scripts, is legacy/reference code and is not the normal shipped path.

Primary flow:

1. `App/TokenStepApp.swift` starts an accessory-style macOS app, claims a single instance, creates `AppState`, and exposes a SwiftUI `MenuBarExtra`.
2. `Stores/AppState.swift` is the `@MainActor` observable application coordinator. It loads settings/snapshots, schedules energy-aware refreshes, invokes quota/rank/update services, and supplies all views.
3. A refresh calls `DataService.runCollectorInHelper`. The bundled `TokenStepHelper` process performs collection away from the UI process, with a 120-second timeout.
4. `Services/UsageCollector.swift` reads only local usage metadata, normalizes source-specific events into `UsageRecord`, deduplicates overlapping proxy/native records, derives cumulative Codex deltas, estimates cost, and aggregates a `UsageSnapshot`.
5. `Services/DataService.swift` validates accounting migrations, atomically writes the snapshot/checkpoint/settings files, and preserves the prior snapshot if recalibration is incomplete.
6. SwiftUI views render `AppState.snapshot`; views must not implement their own collection or freshness rules.

Important source files:

- App lifecycle: `TokenStepSwift/Sources/TokenStepSwift/App/TokenStepApp.swift`
- Central state: `TokenStepSwift/Sources/TokenStepSwift/Stores/AppState.swift`
- Data models/settings: `TokenStepSwift/Sources/TokenStepSwift/Models/UsageModels.swift`
- Collector and accounting: `TokenStepSwift/Sources/TokenStepSwift/Services/UsageCollector.swift`
- Persistence/helper bridge: `TokenStepSwift/Sources/TokenStepSwift/Services/DataService.swift`
- Experimental providers: `TokenStepSwift/Sources/TokenStepSwift/Services/AgentSources/AgentSources.swift`
- Freshness/energy policies: `Support/FreshnessPolicy.swift`, `Support/EnergyRefreshPolicy.swift`
- Popover and dashboard: `Views/PopoverPanelView.swift`, `Views/MainWindowView.swift`
- Update client/installer: `Services/UpdateService.swift`, `Sources/TokenStepHelper/main.swift`
- Local paths: `Support/AppPaths.swift`
- Product and data contracts: `docs/DATA_TRUST.md`, `docs/PRIVACY.md`, `docs/AGENT_SUPPORT.md`, `docs/sync/CONTRACT.md`

## Collection and accounting rules

Official/default sources:

- Codex: `~/.codex/sessions/**/*.jsonl`; archived sessions are intentionally excluded by the current default collector. Codex token events are cumulative counters, so TokenStep derives deltas and handles resets, forks, replay, nested/parallel subagents, partial tails, rewrites, and Shanghai-midnight splits. A local SQLite incremental cache avoids rescanning all JSONL. Codex `state_5.sqlite` is a fallback.
- Claude Code: `~/.claude/projects/**/*.jsonl`; uses per-message usage metadata and deduplicates assistant content blocks by message ID.
- CC Switch Proxy: experimental overlap source from `~/.cc-switch/cc-switch.db` table `proxy_request_logs`; only successful rows with positive token usage are accepted and then cross-source deduplicated.

Experimental sources are off by default. The registry currently supports Gemini CLI, Qwen Code, Kimi Code, OpenCode, TeleAgent, Amp, Droid, and Grok Build. TeleAgent reads only assistant usage/model/time metadata from the OpenCode-compatible `~/.local/share/TeleAgent/teleagent.db` message table, joins `session.directory` by session ID for the authoritative project directory (falling back to message `path.cwd`), and never queries message parts/body content. Legacy experimental collectors also cover ZCode, Hermes Agent, and WorkBuddy. New sources must read authoritative local usage fields only; never estimate usage from prompt/response text.

`UsageCollector.codexAccountingRevision` is currently `8`. Change it only when Codex token results can change. Do not use it for storage migrations, pricing updates, or another provider. Codable storage additions must remain backward-compatible through optional/default decoding.

Aggregation uses the `Asia/Shanghai` day boundary. The output contains totals, daily rows, hourly rhythms, agent-work metrics, tool/model/project breakdowns, source diagnostics, and cost estimates. Project names are reduced to the final path component and sanitized; full paths must not enter snapshots or sync buckets.

## Persistence, privacy, and network boundaries

Runtime data lives below `~/Library/Application Support/TokenStep`:

- `data/usage.json`: authoritative local aggregate snapshot.
- `cache/collector-cache.json`: general file cache.
- `cache/codex-incremental.sqlite3`: incremental Codex session/accounting cache.
- `cache/collection-checkpoint.json`: unchanged-source skip checkpoint.
- `cache/claude-quota-cache.json`: short-lived Claude quota cache.
- `cache/freshness-state.json`: safe attempt timestamps/error categories.
- `config/settings.json`: user settings.
- `updates/` and `logs/`: downloaded updates and installer logs.

Privacy invariants:

- Normal usage collection is local-only and must not upload prompt text, response text, code, credentials, complete paths, or project files.
- Freshness errors shown or persisted must use safe categories, not raw sensitive error text.
- Quota, rank, experimental-source, and future sync features remain explicit opt-ins where documented.
- Local `usage.json` remains authoritative even if multi-device sync is later enabled; remote buckets merge only in the presentation layer.

Expected network activity is limited to optional features:

- GitHub Releases API/DMG download for update checks and updates.
- Anthropic OAuth usage API after reading the local Claude Code Keychain token, only when quota display is enabled.
- Codex quota uses the local `codex app-server` process, not a TokenStep-owned remote API.
- `zhenganhuo.com` public token leaderboard only when rank visibility is explicitly enabled.
- Device sync endpoints are specified but no production `SyncTransport` is implemented yet.

## UI and state conventions

- `AppState` owns mutable product state. Keep it on the main actor and perform heavy collection in the helper/detached utility task.
- Keep freshness calculation in `FreshnessPolicy`, scheduling/backoff in `EnergyRefreshPolicy`, and views presentation-only.
- The six freshness states are `neverSucceeded`, `fresh`, `aging`, `stale`, `partial`, and `disabled`. Never present “0” when the state actually means no successful capture.
- Use the localization helper `L(...)` for user-visible strings. Run both localization validation scripts before packaging.
- Theme, language, menu-bar/Token Island appearance, and screenshot render paths are intentionally shared; UI changes should be checked in normal and screenshot rendering modes.
- The app is `LSUIElement`, single-instance, and uses an accessory activation policy. Do not introduce Dock-centric assumptions.

## Build and dependency route

There are no third-party Swift package dependencies. The app uses Apple frameworks (`SwiftUI`, `AppKit`, `Foundation`, `CryptoKit`) and system SQLite (`SQLite3`), plus macOS command-line utilities where needed.

`TokenStepSwift/Package.swift` exists primarily for SwiftPM tests and declares macOS 14. The distributable app is not produced by `swift build`: use the root scripts.

Build path:

1. `./script/build_and_run.sh` delegates to `script/build_swiftui_and_run.sh`.
2. Localization checks run first.
3. All production Swift files are compiled directly with `swiftc` for macOS 14. The default target is arm64; `TOKENSTEP_ARCH=x86_64` is the supported Intel override.
4. A second executable, `TokenStepHelper`, is compiled from explicitly listed shared files plus `Sources/TokenStepHelper/main.swift`. When adding or moving helper dependencies, update this explicit source list.
5. The script manually assembles `TokenStepSwift/dist/TokenStep.app`, copies the icon/helper, and generates `Info.plist` (`com.huangshu.TokenStep`, `LSUIElement=true`).
6. By default it launches the app; `--no-launch` only builds, and `--verify` launches then checks the process.

Common commands, run from the repository root:

```bash
swift test --package-path TokenStepSwift
./script/build_swiftui_and_run.sh --no-launch
./script/build_and_run.sh --verify
```

CI on `macos-15` runs Swift tests, collector/migration/update/freshness/project/source/device fixtures, settings-card rendering, and a no-launch app build. See `.github/workflows/ci.yml`; reproduce relevant fixture scripts for collector or persistence changes.

## Packaging, signing, notarization, and installation

Public packaging requires an Apple Developer ID Application certificate. The packaging script removes and recreates the repository `release/` directory, so preserve any manual artifacts before running it.

```bash
TOKENSTEP_VERSION=0.2.0 \
CODE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
./script/package_release.sh
```

Add `TOKENSTEP_NOTARY_PROFILE=<notarytool-profile>` and `--notarize`, or provide `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`, for notarization.

Packaging route:

1. Rebuild the app/helper with the requested version.
2. Copy to an isolated temporary work directory.
3. Sign the helper first, then the app with hardened runtime/timestamp; verify signatures.
4. Create `release/TokenStep-<version>.zip` with `ditto`.
5. If requested, submit ZIP to `notarytool`, staple the app, validate, and recreate ZIP.
6. Create a compressed UDZO DMG containing `TokenStep.app` and an `/Applications` symlink; retry DMG creation up to three times.
7. Sign the DMG; optionally notarize/staple it; validate with `codesign`, `spctl`, and `stapler`.

The manual GitHub Actions release workflow imports a base64 P12 into a temporary keychain, calls the same packaging script with notarization, and publishes DMG and ZIP under tag `v<version>`.

End-user installation is drag-and-drop from the DMG to `/Applications`. In-app updates fetch the latest GitHub release DMG, optionally verify Gatekeeper/codesign, then launch a copied `TokenStepHelper`. The helper mounts read-only, verifies version/signature, backs up the installed app, installs with `ditto`, relaunches, and rolls back on failure.

## Testing expectations

At minimum after Swift changes:

```bash
swift test --package-path TokenStepSwift
./script/build_swiftui_and_run.sh --no-launch
```

Run the matching fixture scripts after changes to collection, storage, migration, update, rendering, or sync. High-value scripts include:

- `script/test_codex_cumulative_collector.sh`
- `script/test_ccswitch_proxy_collector.sh`
- `script/test_usage_recalibration_migration.sh`
- `script/test_update_helper_transaction.sh`
- `script/test_freshness_model.sh`
- `script/test_project_extraction.sh`
- `script/test_agent_sources.sh`
- `script/test_device_sync.sh`
- `script/render_settings_cards.sh`

Do not run public release packaging merely to validate ordinary code changes; it requires signing credentials and recreates `release/`.

## Known gaps and cautions

- `docs/COLLECTION_GAP_AUDIT.md` records a verified cost-estimate mismatch when CC Switch forces detailed Codex records: tokens remain identical, but detailed estimated cost can be about 9.4% higher than the summary path. Treat token counts as authoritative for product progress; do not silently claim cost parity until this is fixed and benchmarked.
- Multi-device sync is contract/client-model work only. `DisabledSyncTransport` intentionally traps if used; do not expose the feature until a reviewed production transport, authentication, opt-in UI, and privacy tests exist.
- The direct build script has an explicit helper source list and a VFS overlay workaround for conflicting Command Line Tools Swift module maps. Preserve both unless verified unnecessary on supported toolchains.
- Pricing is embedded in Swift collector logic; `config/pricing.json` belongs to the older Python path and is not the production Swift source of truth.
- Source logs can be rewritten, truncated, forked, or partially written. Preserve fingerprinting, staging transactions, atomic persistence, cache-rebuild fallback, and prior-snapshot protection when changing collection code.

## Local verification status (2026-08-14)

- Static source, script, workflow, and contract analysis completed.
- Initial SwiftPM/build attempts failed because the default user Clang/SwiftPM module caches were unavailable and stale interfaces produced a misleading compiler/SDK mismatch. Using fresh temporary caches (`CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE`) resolved compilation.
- `script/test_agent_sources.sh` now builds for the host architecture by default and passed all synthetic source fixtures on x86_64, including TeleAgent detection, assistant-only filtering, token/cache accounting, explicit total, model, session, and project extraction.
- The complete app and bundled helper both built successfully for the default arm64 target and for `TOKENSTEP_ARCH=x86_64`. The final local artifact under `TokenStepSwift/dist/TokenStep.app` is currently x86_64, version 0.2.0, minimum macOS 14.
- A forced read-only collection against the installed TeleAgent 2.2.1 database succeeded after joining `message.session_id` to `session.directory`: source status `ok`, 574 valid usage records and 35,069,912 tokens at verification time. Project attribution resolved to `Obsidian Vault`, `waytoagitrain`, and `TeleAgent的工作空间`; only eight assistant rows lacked a session directory and remained unnamed. The resulting local TokenStep snapshot was updated successfully.
- The full SwiftPM XCTest suite was not rerun after the TeleAgent change; the focused compiled fixture, production builds, localization checks, shell syntax checks, and live read-only snapshot verification passed.

## Change checklist

Before finishing a change:

1. Confirm whether the touched path is production Swift or legacy Python.
2. Preserve local-first/privacy and opt-in boundaries.
3. Keep storage decoding backward-compatible and decide explicitly whether a Codex accounting revision bump is warranted.
4. Add or update focused unit/fixture tests.
5. Run Swift tests and a no-launch app build; run relevant shell fixtures.
6. If user-visible text changed, ensure `L(...)` coverage and localization checks pass.
7. If helper-shared code changed, confirm the explicit helper compile list still closes over all dependencies.
8. If release behavior changed, validate signing/notarization/rollback logic without exposing credentials.
