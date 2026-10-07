# Supabase 部署与验证记录

验证日期：2026-10-07（Asia/Shanghai）。

## 部署目标

- 组织：`ngocvychu38-web's Org`
- 项目：`TokenStep`，新加坡 `ap-southeast-1`
- Project ref：`hdizeqfyrdfbqohrnuzt`
- Project URL：`https://hdizeqfyrdfbqohrnuzt.supabase.co`
- Publishable Key：`sb_publishable_uk6GCUIH9eF8AZjMe-94ww_5j2mIOPS`（公开客户端标识，不是管理密钥）
- [Dashboard](https://supabase.com/dashboard/project/hdizeqfyrdfbqohrnuzt)
- 正式 workspace：`e59b5c17-4065-4b8b-8214-ecb3e0e72181`，名称 `TokenStep`
- 本机 device：`269994bd-08b4-4a41-bb09-3dd493a92e0c`

两个 migration 已成功执行。`enroll-device`、`ingest-usage` 均为 ACTIVE，版本 2，固定依赖 `@supabase/supabase-js@2.117.2`。平台 `verify_jwt=false` 是有意配置：注册由短期一次性注册码鉴权，上传由独立设备秘密的 SHA-256 校验和设备 enabled/revoked 状态鉴权；不是无鉴权写接口。

## 已执行验证

| 验证 | 结果 |
| --- | --- |
| Rust enroll → 真实 HTTPS 函数 → pgcrypto 哈希 → devices | 成功 |
| Rust sync → 真实 HTTPS 函数 → usage_buckets | HTTP 200，accepted=362 |
| 本地快照与数据库数量及 Token 合计 | 362 桶、2,691,232,002 Token，一致 |
| 同一快照再次上传 | accepted=0，duplicate_or_older_snapshot，合计未增加 |
| 错误注册码 | HTTP 401 enrollment_rejected |
| 缺失/错误设备凭证 | HTTP 401 |
| Publishable Key 匿名读取 usage_dashboard | HTTP 401，权限拒绝 |
| 数据库 authenticated + workspace 成员 | 可读取 362 桶 |
| 数据库 authenticated + 非成员 | 读取 0 桶，注册 RPC 被拒绝 |
| 来源失败快照 | 原 Token 数据保留 |
| 禁用设备 | 入库被拒绝 |

数据库权限测试使用事务内临时 auth 用户/JWT claim 模拟，全部 rollback：没有遗留测试账号，也没有改变正式数据。该项验证 RLS 本身，**不等同于完成 Supabase Auth 密码登录或 SwiftUI UI 验收**。

初次上传分量：Codex 298 桶 / 2,217,452,465 Token；TeleAgent 57 桶 / 438,073,126 Token；Claude Code 7 桶 / 35,706,411 Token。这是现阶段 Rust 采集快照的累计值，非当天消耗，也不是计费数；Codex 分叉/重放与旧 Swift 口径对账尚未完成。

## 可独立复核

在 Dashboard SQL Editor 执行：

```sql
select device_name, os_family, os_version, architecture,
       agent_name, count(*) as buckets, sum(total_tokens) as tokens
from public.usage_dashboard
group by device_name, os_family, os_version, architecture, agent_name
order by tokens desc;

select count(*) as buckets, sum(total_tokens) as tokens
from public.usage_buckets;

select device_id, agent_key, state, last_succeeded_at
from public.source_sync_status order by agent_key;
```

本机快照（包含用量元数据，不上传对话正文）：
`/Users/macforai/Library/Application Support/TokenStep/agent/snapshot.json`。
设备凭证保存在本机 Keychain，未提交 Git；服务端仅保存哈希。

重复上传复核（仓库根目录）：

```bash
cargo run -p tokenstep-agent -- sync \
  --input '/Users/macforai/Library/Application Support/TokenStep/agent/snapshot.json' \
  --ingest-url https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage
```

## 安全检查结论

已收紧 trigger-only 函数默认 PUBLIC/anon/authenticated EXECUTE 权限，private 凭证/注册码表启用 RLS 并撤销客户端表权限；补齐外键和 device/generated_at 索引。

安全 Advisor 剩余提示均为有意设计：

- private 两张表无 RLS policy：客户端默认拒绝，仅内部 security-definer 函数访问。[说明](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)。
- authenticated 可执行 create_device_enrollment_code：函数内部检查 workspace owner/admin；非成员拒绝已实测。[说明](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)。

## 尚需完成

2026-10-07 已核实用户自行创建的正式账号邮箱已确认，并将其绑定到 TokenStep workspace：显示名 `macforai`，角色 `owner`。以该账号的数据库 authenticated/JWT claim 上下文验证 RLS，能够读取 362 桶、1 台机器、3 个 Agent，合计 2,691,232,002 Token。该验证未使用用户密码，不代表已完成 Auth 密码登录或 SwiftUI 实际登录；这两项需用户在本机应用输入密码后继续确认。

2026-10-07 已部署 hourly_usage migration，完成小时数据 SQL 回传测试。Mac LaunchAgent 已安装，StartInterval=60，安装后的 Rust 二进制已采集 362 桶、2,701,258,857 Token，全部包含小时汇总并通过 verify。首轮后台上传在 macOS Keychain 读取处等待用户授权（进程采样确认），目前尚未验证连续定时上传成功。授权后须核对至少两轮 cycle_ok 与 ingestion_runs 时间；不能将任务已安装等同于上传已成功。Windows 实机采集与安装仍待验证。

新版 Intel 应用已安装并启动，安装二进制与构建产物 SHA-256 一致（c0e2f08ca81b7b40c6f52b4b0f7936859209e20d80a9b583ceade0905b4bac95）。旧应用保存在 tokenhub/tokenstep-cloud-pages-backup.XKPgYx/TokenStep.app。Rust 11 项测试、clippy、PGlite 云端 SQL 测试、Swift 云端转换 fixture 和 Intel 完整构建通过；SwiftPM XCTest 因本机 CLT 缺少 XCTest 无法运行。验收步骤见 CLOUD_MIGRATION_VERIFICATION.md。
