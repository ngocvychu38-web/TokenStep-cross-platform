# TokenStep 跨平台采集与 Supabase 验收手册

本文档对应 `codex/rust-cross-platform` 分支。每一个门禁均可独立执行；前一个门禁失败时，不进入下一项。

## 当前实现范围

- Rust 公共采集核心：Codex、Claude Code、TeleAgent、OpenCode。
- 实验性 JSON 日志适配：Gemini CLI、Qwen Code、Kimi Code、Grok Build、Amp、Droid、WorkBuddy；尚未完成每种来源的实机对账。
- macOS Intel 与 Windows x64 路径适配。
- `UsageBucketV1`：保留日期、设备、系统、Agent、模型、项目和 Token 分量。
- 本地 JSON 自校验。
- 设备一次性注册码、独立设备凭证、Supabase 原子入库函数。
- SwiftUI 云端页：登录 Supabase 后查询 `usage_dashboard`。
- Windows 计划任务安装脚本。

## 验证状态与仍待完成的工作

已在 Intel Mac 验证 Rust 测试、真实日志采集及 SwiftUI 编译。PGlite（Postgres WASM）测试实际执行 migration 与 SQL 函数，验证注册、入库、重复上传、RLS、来源失败保留、事务回滚和设备撤销。PGlite 中仅为测试替换 pgcrypto，生产 migration 保留真实 pgcrypto。2026-10-07 已正式部署 Supabase 与两个 Edge Functions，完成真实注册、上传、重复上传及数据库权限验证；详情见 [云端部署报告](SUPABASE_DEPLOYMENT.md)。正式用户 Auth 登录和 SwiftUI 登录读数仍待用户设置账号后验证。

数据库模块独立验证：

```bash
cd tools/cloud-tests
npm ci --ignore-scripts
npm test
```

当前仍保留原 Swift 本地统计页面，云端页面独立读取 Supabase。完整迁移还需完成：其他 Agent 的 Rust 适配器与真实样本对账、Codex 分叉/重放/子 Agent 口径与 Swift 的对账、Mac 后台安装与 Windows 实机验证。设备凭据使用 keyring 保存到 macOS Keychain / Windows Credential Manager，不使用明文文件回退。凭据库不可用时注册会明确报错；后台任务必须以注册时的同一用户身份运行。[keyring 官方说明](https://docs.rs/keyring/4.2.0/keyring/v1/index.html)。

`cycle` 先将快照写入 SQLite `outbox.sqlite3`，再按顺序上传。网络失败时未确认批次保留；服务端只接受较新快照。当前统一日期口径仅支持 Asia/Shanghai。

其余实验 Agent 将沿用同一 `SourceAdapter` interface 继续迁移；在真实 Windows 样本验证前不宣称已支持。

## 门禁 0：确认代码备份

```bash
git fetch origin
git log origin/codex/local-backup-20261006 -1 --oneline
git branch --show-current
```

预期：备份提交为 `c556839`，当前分支为 `codex/rust-cross-platform`。

## 门禁 1：验证 Rust 采集层

```bash
./script/verify_rust_collector.sh
```

预期：

- Rust 测试全部通过；
- 输出 `collection_ok`；
- 输出 `verification_ok`；
- doctor 分别显示 Codex、Claude Code、TeleAgent 状态；
- 最后显示 `Rust collector verification passed.`。

系统凭据库可独立验证：`cargo run -p tokenstep-agent -- vault-check`。预期 `vault_ok`；仅写入并删除随机测试条目，不访问真实上传凭证。Intel Mac 已完成此验证，Windows 需在实机执行。

手动查看输出结构：

```bash
mkdir -p /tmp/tokenstep-check
cargo run -p tokenstep-agent -- collect \
  --output /tmp/tokenstep-check/snapshot.json \
  --state-dir /tmp/tokenstep-check/state
cargo run -p tokenstep-agent -- verify \
  --input /tmp/tokenstep-check/snapshot.json
```

`snapshot.json` 不应包含 prompt、回复正文、代码、API Key 或完整项目路径。

## 门禁 2：部署 Supabase

需要用户在 Supabase Dashboard 执行：

1. 创建一个 Supabase Project，记录 Project URL 和 Publishable Key。
2. Authentication → Providers 中启用 Email。
3. SQL Editor 中执行：
   `supabase/migrations/202610060001_initial_cloud_schema.sql`。
4. Authentication → Users 中创建第一个登录用户；migration 中的触发器会自动创建个人 workspace。
5. 部署 `enroll-device` 和 `ingest-usage` 两个 Edge Functions。
6. 确认两个函数的 `verify_jwt` 均为 `false`；函数内部使用设备凭证自行鉴权。
7. 在 Edge Function Secrets 中确认存在 `SUPABASE_URL` 和 `SUPABASE_SERVICE_ROLE_KEY`。

如果本机安装了 Supabase CLI：

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
supabase db push
supabase functions deploy enroll-device --no-verify-jwt
supabase functions deploy ingest-usage --no-verify-jwt
```

结构检查：

```bash
./script/verify_cloud_assets.sh
```

## 门禁 3：生成设备注册码

在 Dashboard 的 SQL Editor（postgres 管理身份）查询 workspace：

```sql
select w.id, w.name
from public.workspaces w
join public.workspace_members m on m.workspace_id = w.id
order by w.created_at;
```

然后在 SQL Editor 调用（普通客户端调用要求 workspace 管理员身份）：

```sql
select public.create_device_enrollment_code('<WORKSPACE_ID>');
```

注册码 10 分钟有效且只能使用一次。不要把注册码提交到 Git。

## 门禁 4：注册并上传本机

```bash
cargo build --release -p tokenstep-agent

target/release/tokenstep-agent enroll \
  --enrollment-url 'https://<PROJECT_REF>.supabase.co/functions/v1/enroll-device' \
  --code '<ONE_TIME_CODE>'

target/release/tokenstep-agent collect \
  --output /tmp/tokenstep-snapshot.json

target/release/tokenstep-agent sync \
  --input /tmp/tokenstep-snapshot.json \
  --ingest-url 'https://<PROJECT_REF>.supabase.co/functions/v1/ingest-usage'
```

预期输出：`enrollment_ok`、`collection_ok`、`sync_ok`。

Supabase SQL 验证：

```sql
select display_name, os_family, architecture, last_seen_at
from public.devices order by last_seen_at desc;

select device_name, os_family, agent_name, project_name, model,
       sum(total_tokens) as tokens
from public.usage_dashboard
group by device_name, os_family, agent_name, project_name, model
order by tokens desc;
```

## 门禁 5：验证 SwiftUI 展示层

```bash
TOKENSTEP_ARCH=x86_64 ./script/build_swiftui_and_run.sh
```

1. 打开主窗口 → “多设备数据”。
2. 输入 Project URL、Publishable Key、邮箱和密码。
3. 点击“登录并读取云端数据”。
4. 确认机器数、Agent 数、项目数和 Token 合计与上一步 SQL 一致。
5. 分别切换机器、Agent、项目过滤器，确认结果变化。
6. 切换系统与日期过滤器，确认与相同 SQL WHERE 条件的合计一致。

密码和 access token 只驻留进程内；Project URL、Publishable Key 和邮箱保存在 UserDefaults。

## 门禁 6：Windows 机器

在 GitHub Actions 下载 Windows Release 构建，或在 Windows 上执行：

```powershell
cargo build --release -p tokenstep-agent
```

先运行 `enroll`、`collect`、`verify`、`sync` 四条命令。全部成功后安装计划任务：

```powershell
powershell -ExecutionPolicy Bypass -File .\script\windows\install-tokenstep-agent.ps1 `
  -AgentExe .\target\release\tokenstep-agent.exe `
  -IngestUrl 'https://<PROJECT_REF>.supabase.co/functions/v1/ingest-usage'
```

验证：

```powershell
Get-ScheduledTask -TaskName 'TokenStep Agent'
Start-ScheduledTask -TaskName 'TokenStep Agent'
```

随后回到 Supabase 执行门禁 4 的两条 SQL，确认出现 Windows 设备及对应 Agent/项目数据。

## 门禁 7：断网、重复上传和权限验收

- 离线队列：注册后执行 `cycle --ingest-url https://127.0.0.1:1`，预期网络失败且 SQLite 保留批次；恢复正常 URL 后再次 cycle，应输出 `batch_acknowledged`。
- 重复上传：将同一 snapshot sync 两次，第二次应返回 `duplicate_or_older_snapshot`；数据库 Token 合计保持不变。
- 权限：另建一个测试用户，以该用户登录云端页面，确认看不到第一个用户的机器或 Token。
- 设备撤销：在 SQL Editor 将测试设备 `enabled` 设为 false，再上传应得到 401。
- 采集失败：用测试快照将某来源 state 改成 query_failed 并删除该来源 buckets；上传后原来源的历史桶应保留，source_sync_status 应显示失败。

## 故障隔离

- `doctor` 为 `missing`：该 Agent 的候选目录不存在。
- `missing_valid_rows`：存在日志/数据库，但没有权威 usage 字段。
- `query_failed`：SQLite 无法读取或 schema 已变化。
- `401 enrollment_rejected`：注册码过期或已使用。
- `401 ingestion_rejected`：设备凭证无效、设备被禁用或 payload 不符合契约。
- 云端 SQL 有数据而 UI 没有：检查登录用户的 workspace membership 与 RLS。
