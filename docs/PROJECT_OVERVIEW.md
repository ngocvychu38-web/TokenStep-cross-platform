# TokenStep 功能与技术架构

版本基线：2026-10-11，Swift 前端 0.2.0 / Rust 代理 0.1.0，开发分支 `codex/rust-cross-platform`。以当前代码为准；旧版文档中的“仅本地读取”和未启用 SyncTransport 不代表现在的 Supabase 路径。

## 1. 产品定位与功能架构

TokenStep 是多设备 AI Agent Token 用量采集和可视化工具。设备上的代理读取已有使用元数据，上传汇总；Mac 前端按工作空间权限查询和展示。不拦截模型请求，不从聊天字数猜测 Token，也不是各模型供应商的计费后台。

| 功能域 | 当前能力 | 边界 |
| --- | --- | --- |
| 多设备采集 | Intel Mac / Windows x64，独立设备 UUID、名称、系统及架构 | 设备关机、休眠或用户退出登录时不能持续采集 |
| 今日用量 | 目标圆环、Token 合计、Agent/模型/项目统计、金额估算 | 展示工作空间汇总；API 列表价估算不是实际账单 |
| 历史与统计 | 日趋势、活动墙、小时节奏、历史日期和项目统计 | 缺少时间戳的 Token 不编造活跃时段 |
| Agent 工作强度 | 来源筛选、小时分布、记录活跃时段、Token 指标 | 未提供权威调用次数与完整缓存覆盖率的字段显示不可用 |
| 多设备页 | 设备、OS、Agent、项目、日期筛选和明细 | 其他机器只显示它们最后上传的数据 |
| 手动刷新 | 本机立即采集上传 → 读取 Supabase → 应用共享快照；强制刷新可见榜单 | 最多约 120 秒等待采集/锁；不能远程强制 Windows 即时采集 |
| 定时刷新 | 后台周期采集上传；前端每 60 秒查询云端 | 触发间隔不是“上传完成时间间隔”，采集与网络耗时另计 |
| 分享与截图 | 今日卡片、节奏卡等导出 PNG，复用相同展示模型 | 不自动上传生成的图片 |
| 原生交互 | 菜单栏、浮层、主窗口、主题、语言、目标、自动启动 | GUI 仅 macOS 14+；本次交付仅 Intel 构建 |
| 授权 | Supabase Email 登录；workspace owner/admin/member/viewer；RLS | 工作空间成员共享授权数据，不等于内部按成员归属的消耗排行榜 |
| 外部排行榜 | 独立公共榜单、排序、当前身份高亮、可选显示 | 与 Supabase 用户/工作空间不是同一账号系统，不能混为团队真实用量 |
| 更新与额度 | 原有更新器、Quota 服务和本地 Swift Collector 保留 | Quota 在当前云端路径关闭；上游更新不能保证包含此分支改造 |

## 2. 三层技术架构

```text
每台 Mac / Windows 的 Agent 原始元数据（JSONL / SQLite / protobuf 数值字段）
  ↓ SourceAdapter（只读，不读取对话正文）
Rust tokenstep-core：UsageFact → 去重/累计计数差分 → UsageBucketV1
  ↓ 日期 × Agent × 模型 × 项目，附小时汇总
Rust tokenstep-agent：校验 → snapshot.json → SQLite Outbox → HTTPS 上传
  ↓ 独立设备凭据；成功 ack 才删除队列
Supabase Edge Functions：enroll-device / ingest-usage
  ↓ 设备凭据哈希鉴权、Postgres 原子入库
Postgres：workspace / member / device / usage_buckets / source_sync_status / ingestion_runs
  ↓ Supabase Auth + RLS + security_invoker usage_dashboard
Mac SupabaseCloudStore：登录/续期/分页查询
  ↓ CloudSnapshotAdapter → AppState.snapshot（无本地统计回退）
今日 / 历史 / 统计 / Agent 工作强度 / 菜单栏 / 分享卡
```

后台采集与展示进程独立。退出 Mac 展示应用不会停止代理；Windows 无需安装 GUI。Swift 保留的旧 Collector/Helper 供历史功能和对账使用，正常云端展示不再通过它采集数据。

### 2.1 采集与上传层

- Rust edition 2024，Cargo workspace：`rust/tokenstep-core` 和 `rust/tokenstep-agent`。
- `serde`/`serde_json` 解析和序列化；`rusqlite` bundled SQLite 读源库及保存 Outbox；`chrono` 处理时间；`walkdir` 发现文件；`sha2` 生成脱敏项目键；`uuid` 生成设备标识。
- `reqwest` blocking + rustls TLS 发 HTTPS；`keyring` 使用 macOS Keychain / Windows Credential Manager；`clap` 提供 CLI；`tempfile` 支持原子文件替换。
- `collect`、`verify`、`doctor` 用于本地独立验证；`enroll` 注册设备；`sync` 手动上传指定快照；生产后台运行 `cycle`；Mac `install-schedule` 安装用户 LaunchAgent。
- `cycle.lock` 防并发。网络/服务端失败保留待上传批次；收到正确 ack 后删除，不因单纯 HTTP 请求已发出就丢弃数据。
- Mac LaunchAgent、Windows Scheduled Task 均按已登录用户运行；不是系统级无人登录服务。

### 2.2 Supabase 层

- Postgres 保存工作空间、用户成员、设备和日用量桶；`hourly_usage` 为 JSONB。
- Supabase Auth 为前端登录签发访问令牌；JWT + RLS 限定读取范围。
- Edge Functions 为 Deno/TypeScript，固定依赖 `@supabase/supabase-js@2.117.2`。
- `enroll-device` 消费一次性注册码，创建独立设备上传凭据；注册码 10 分钟有效且一次性。
- `ingest-usage` 验证设备凭据哈希、启用状态，再调用数据库函数原子入库。两个函数使用自定义鉴权，所以 `verify_jwt=false`；这不代表无鉴权。
- service-role key 仅位于服务端环境。前端只有 Publishable Key；代理只持有自己的设备凭据。
- 同一日桶按设备、日期、Agent、模型、项目覆盖更新，不按每次上传累加。重复/旧快照不会增加消耗；失败来源不覆盖此前成功来源的数据。

### 2.3 展示层

- SwiftUI + AppKit + Foundation + Security + CryptoKit + 系统 SQLite；没有第三方 Swift 包依赖。
- `SupabaseCloudStore` 集中登录、访问令牌续期、分页加载 `usage_dashboard` 与 `source_sync_status`。
- `CloudSnapshotAdapter` 将联合维度行转换成旧 UI 的日、来源、模型、项目和小时展示模型；金额复用 `TokenCostEstimator` 估算。
- `AppState` 主线程管理快照、刷新状态、设置和视图；视图不自行读取源日志。
- `ManualUsageRefreshService` 在 utility 线程调用已安装 Rust 代理，处理锁占用、失败和超时；完成上传后再读云端。
- 登录密码按项目/账号保存在 Keychain；access/refresh token 仅在进程内；主动退出登录删除保存的登录密码，并清空页面快照。
- 单次云端请求失败保留最近成功数据并提示，不回退旧本地 `usage.json`。

## 3. 各 Agent 的 Token 获取路线

| Agent | 当前 Rust 数据源 | 口径及验证边界 |
| --- | --- | --- |
| Codex | `~/.codex/sessions/**/*.jsonl` | 累计 Token 计数差分、重置、缓存/推理分项；Rust 与旧 Swift 的分叉、重放、子 Agent 完整口径仍待系统对账；默认不读 archived |
| Claude Code | `~/.claude/projects/**/*.jsonl` | assistant/message usage 字段，按消息标识处理重复内容 |
| TeleAgent | OpenCode 兼容 `teleagent.db` | assistant 用量；连接 session.directory 确定项目，保留缓存/输入/输出，不查询消息正文 |
| OpenCode | `opencode.db` | 复用相同 SQLite 用量路线；Windows 同时发现 LOCALAPPDATA 路径 |
| Antigravity（实验） | `~/.gemini/antigravity/conversations/*.db` 等 | 读取 gen_metadata.data、steps.metadata 数值字段和摘要 workspace；私有 protobuf wire 格式，不是公开稳定接口；字段缺失跳过，不估算正文 |
| Gemini CLI、Qwen Code、Kimi Code、Grok Build、Amp、Droid、WorkBuddy（实验） | 各自目录内 JSON/JSONL 的显式 usage/tokens 字段 | 有通用及部分专用适配，不能因目录存在就宣称实机完整支持 |

Rust 当前注册 12 类来源。Hermes、CC Switch、ZCode 等旧 Swift 源不能据此视为已迁移到 Rust。WSL 文件系统不自动扫描；Agent 若修改日志格式/位置，需补路径或适配器并重新对账。

统一日期时区为 Asia/Shanghai（UTC+8），小时桶也使用这个时区。`total_tokens` 来自源显式总数或已知分项；reasoning 等包含于输出的分项不得再次叠加。缓存分项定义以各源适配器为准，不能把各字段全相加当总数。

## 4. 关键数据模型

| 实体 | 用途 |
| --- | --- |
| UsageFact | 一条标准化用量事实：时间、来源事件标识、Agent、模型、项目及 Token 分项 |
| UsageBucketV1 | 一天 × Agent × 模型 × 项目的联合桶，附 0–23 小时汇总 |
| CollectionSnapshot | 设备、生成时间、日桶和来源诊断；上传完整快照 |
| workspaces / workspace_members | 数据授权边界；成员角色，不是 Token 数据维度中的 user_id |
| devices | UUID、名称、OS、版本、架构、工作空间、启用状态 |
| usage_buckets | 联合维度 Token 和 hourly_usage；重复上传幂等 |
| source_sync_status | 来源状态、文件/记录数、最后尝试/成功时间 |
| ingestion_runs | 入库流水，关联生成时间与接收时间 |
| private.device_credentials / enrollment_codes | 上传凭据及注册码哈希；不向普通客户端暴露 |

同名项目在旧 UI 的名称汇总中可能合并；精确项目标识、设备区分以多设备明细为准。当前团队内没有自动按使用者标识归属模型用量的完整机制。

## 5. 安全、日志和已知限制

- 只上传安全元数据和汇总，不上传源码、对话正文、完整项目路径和凭据。项目名仍是会上传的统计元数据，应避免把敏感信息写进项目名称。
- 代理日志：`agent/logs/agent.log`、`agent-error.log`；手动刷新：`manual-refresh.log`；前端：`logs/lifecycle.log`；服务端：Edge Logs + ingestion_runs。
- 使用设备请求 UUID、generated_at、接受桶数及前端总数做跨层对账；详细步骤见 [日志文档](PIPELINE_LOGS.md)。
- `missing` 表示没发现源，不是上传失败；`missing_valid_rows` 表示存在但没有识别出的用量。后台周期不保证整点一分钟完成。
- Windows CI 成功不等于每台真实电脑全部 Agent 格式已验证。现有前端日志已出现 3 台设备，不应将它推论为所有 Windows 场景覆盖。
- 安装包未签名/公证；公开分发、自动升级信任链、长周期日志轮转、Rust/Swift Codex 全口径对账仍需独立建设/验证。

## 6. 代码索引与构建

```text
rust/tokenstep-core/          跨平台路径、适配器、标准模型、联合聚合
rust/tokenstep-agent/         CLI、凭据、Outbox、定时安装、上传
supabase/migrations/          表、RLS、函数、视图、安全加固、小时数据
supabase/functions/           设备注册及入库 Edge Functions
TokenStepSwift/Sources/       AppState、云端服务、适配器、SwiftUI 页面、旧 Collector
script/windows/              安装、卸载、打包及 Windows fixture
script/test_cloud_snapshot.sh 云端模型、登录日志、手动刷新验证
.github/workflows/ci.yml      Windows/macOS Rust、SQL、Swift、打包检查
docs/                        部署、验证、隐私、历史设计及本交付资料
```

Rust：`cargo test --workspace`、`cargo clippy --workspace --all-targets -- -D warnings`、`cargo build --release -p tokenstep-agent`。Windows Release 使用 `-C target-feature=+crt-static`，不要求目标电脑安装 Rust。

Intel UI：`TOKENSTEP_ARCH=x86_64 ./script/build_swiftui_and_run.sh --no-launch`，直接 swiftc 编译 App 与 Helper，手动组装 .app。`swift test` 用于测试，不是正式应用打包入口。Apple Silicon 需单独 arm64 构建，此交付不混入 arm64 二进制。
