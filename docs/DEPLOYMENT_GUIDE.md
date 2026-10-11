# 安装部署与独立验收

适用分支：`codex/rust-cross-platform`。交付日期：2026-10-11。安装包及校验值见 [安装包清单](DISTRIBUTION_MANIFEST.md)，整体架构见 [项目架构](PROJECT_OVERVIEW.md)。这是一份内部测试部署指南；不要用上游原版 DMG 替换本分支的云端版本。

## 1. 部署前确认

| 组件 | 条件 | 已预置 / 仍需填写 |
|---|---|---|
| Mac 展示端 | Intel Mac，macOS 14+ | 公开 URL/Publishable Key 可通过随包脚本设置；需要 Supabase 邮箱、密码 |
| Mac 采集端 | 同一个使用 AI 工具的登录用户 | 新设备需要一次性注册码；已有本机注册无需重复 |
| Windows 采集端 | Windows x64、PowerShell、当前用户任务计划程序 | 后端地址、1 分钟周期已预置；每台电脑各需一个注册码 |
| 后端 | Supabase Auth、Postgres、Edge Functions | 当前项目已部署；迁移到新项目才需完整部署 |

现有后端：`https://hdizeqfyrdfbqohrnuzt.supabase.co`。现有工作空间：`e59b5c17-4065-4b8b-8214-ecb3e0e72181`。前端账户为 `ngocvychu38@gmail.com`，显示名称 `macforai`。安装包不含密码、设备上传凭据或 service-role key。

Mac 钥匙串授权使用 **Mac 登录密码**；Supabase 登录使用 **Supabase 账户密码**。两个密码不是同一个概念。Windows 仅上传，不需要在代理中填写展示账户密码。

## 2. Intel Mac 安装

1. 解压 `TokenStep-0.2.0-macOS-Intel.zip`，检查 SHA-256（见清单）。退出旧应用，将旧应用移到备份位置，再把随包 `TokenStep.app` 拖到 `/Applications`。保留旧版本以便回退。
2. 双击随包 `configure-cloud.command`，写入当前后端的公开连接参数。此步骤会覆盖这个 App 的两项后端设置；使用其他 Supabase 项目时，在 App 设置页填写该项目地址与 Publishable Key。
3. 打开 App 并登录。内部安装包没有 Apple 公证；如果被系统阻止，仅在确认来源后通过系统设置 → 隐私与安全性批准打开。不要全局关闭 Gatekeeper。
4. 现有本机已注册、已有定时任务时，只更新 App 即可。新 Mac 才执行下面的代理注册及调度步骤。

在终端进入解压文件夹，执行（注册码 10 分钟有效、每台设备只用一次）：

```bash
./tokenstep-agent vault-check
./tokenstep-agent enroll --enrollment-url https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/enroll-device --code '<本设备一次性注册码>'
./tokenstep-agent install-schedule --ingest-url https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage --interval-seconds 60
```

注册码属于短期敏感信息；不要截图分享或提交 Git。示例中的尖括号是占位符，执行时替换；终端历史可能保留输入。钥匙串提示时核实申请者是本包代理，再授权。

安装命令将代理复制到稳定路径 `~/Library/Application Support/TokenStep/agent/bin/tokenstep-agent`，注册当前用户 LaunchAgent `com.tokenstep.collector`。任务仅在用户登录且电脑可运行时工作，不承诺睡眠或关机时采集。App 和代理是两个独立组件；重新构建/更新代理需重新执行安装调度命令，不能仅替换 App。

## 3. Windows 安装（两台电脑分别执行）

1. 完整解压 `TokenStep-Agent-0.1.0-windows-x64.zip`，不要直接在压缩包中运行。
2. 使用实际运行 AI Agent 的 Windows 用户双击 `install.cmd`，输入为该电脑新生成的注册码。不要切换成另一个管理员账户，否则采集目录和凭据所属用户会不同。
3. 安装器校验代理、检查 Windows Credential Manager、注册设备、建立 `TokenStep Agent` 任务并立即运行首次上传。默认周期 1 分钟，无需安装 Rust。
4. Windows 数据在 Mac 的“多设备数据”页面查看。Windows 包不包含桌面展示 App，也不自动扫描 WSL 内的 Agent 数据。

安装目录：`%LOCALAPPDATA%\TokenStep\Agent\bin`；状态与日志：`%LOCALAPPDATA%\TokenStep\agent`。原生默认数据目录之外的工具需要检查 `doctor` 输出；并非每个工具/版本都保证已支持。

任务运行于当前交互登录用户，`IgnoreNew` 防止重叠，不会在用户注销后作为系统服务运行。内部包没有 Windows Authenticode 签名，安全软件可能提示；确认来源和校验值后再允许运行。

## 4. 现有 Supabase：只生成新设备注册码

不需要再次部署数据库。工作空间 owner/admin 可调用注册码 RPC；SQL Editor 的管理权限也可生成。每台电脑各执行一次：

```sql
select public.create_device_enrollment_code(
  'e59b5c17-4065-4b8b-8214-ecb3e0e72181'::uuid
);
```

凭据由注册响应交给设备并存入 OS 凭据库，后端只存哈希。两台 Windows 不能共用一个已消费的码。前端账户与设备上传身份分离；用户必须属于对应 workspace 才能读取设备数据。新增 Auth 用户默认拥有自己的工作空间，**并不自动加入现有工作空间**。管理员应审核用户 UUID，再在 `workspace_members` 添加对应工作空间成员关系；角色包括 owner/admin/member/viewer。不要直接复制设备凭据来“关联账户”。

## 5. 新 Supabase 项目的完整部署

交付目录含 `supabase/migrations`、`supabase/functions` 和 `supabase/config.toml`；仓库中同路径为权威源。不要把旧设备凭据复制到新项目。

1. 创建项目、启用 Email/Password Auth，按组织要求配置邮箱验证和账户创建。保存项目 URL 与 Publishable Key；service-role key 只用于服务端。
2. 按顺序应用迁移：
   - `202610060001_initial_cloud_schema.sql`
   - `20261006233553_cloud_security_hardening.sql`
   - `20261006235908_cloud_hourly_usage.sql`
3. 部署 `enroll-device`、`ingest-usage`。函数使用独立的一次性码/设备凭据鉴权，所以部署时关闭平台默认 JWT 校验；**这不等于无需鉴权**。函数环境要有 Supabase 服务端 URL/service-role 环境变量，不能放进客户端安装包。
4. 创建首个 Auth 用户；触发器为新用户建立 workspace/owner 关系。查询该用户的工作空间 UUID，生成注册码并安装代理。
5. 将 Mac 设置和 Windows `config.json` 改为新项目的公开地址。Windows 配置字段为 `enrollment_url` 与 `ingest_url`；随后重新注册新项目设备。

若使用 Supabase CLI，在安装好并登录 CLI 后，从仓库根目录执行：

```bash
supabase link --project-ref <新项目ref>
supabase db push
supabase functions deploy enroll-device --no-verify-jwt
supabase functions deploy ingest-usage --no-verify-jwt
```

CLI 路线和 SQL Editor 手动路线选一种，避免重复应用同一迁移。上述新项目流程是操作指南，本次交付没有另建一个 Supabase 项目。Edge Functions 使用固定版本的 Supabase JS SDK；数据库 RLS、`security_invoker` 查询视图和私有凭据表是部署的一部分，不能省略安全迁移。

## 6. 每层独立验证

### A. 本地采集：不依赖网络

Mac 在安装包目录运行，Windows 将命令改为 `.\tokenstep-agent.exe`：

```bash
./tokenstep-agent doctor
./tokenstep-agent collect --output snapshot.json
./tokenstep-agent verify --input snapshot.json
```

先用 `--help` 核对当前命令参数。检查快照里的 device、OS、agent、project、model、输入/输出/缓存 token 和日期；与一个已知会话的原始 usage 数字对账。生成的快照属于本机数据，不要提交仓库。“未安装/没有数据”不同于“解析失败”；不能把解析失败当成真实零消耗。合成测试通过不代表所有 Agent 的真实版本都完成对账。

### B. 上传与后端：不依赖前端

```bash
./tokenstep-agent cycle --ingest-url https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage
```

查看日志确认采集完成、HTTP 成功及服务器确认；HTTP 200 之外还要检查确认内容与入库记录。SQL Editor 可独立检查：

```sql
select * from public.devices order by created_at desc;
select * from public.ingestion_runs order by created_at desc limit 20;
select * from public.source_sync_status limit 50;
select * from public.usage_buckets limit 20;
select * from public.usage_dashboard limit 20;
```

预期新设备出现、上传被接受、对应维度的 token 已入库。重复上传同一完整快照不应累加翻倍；较旧快照不能覆盖较新的数据。失败来源旧数据保留，不能因此要求各表每次都整体清零。管理 SQL 能读到数据不等于客户端 RLS 正确：还应使用有权限账户验证可读，用另一个工作空间账户验证不可读。

### C. 展示：只读 Supabase

登录有权限账户，打开“多设备数据”，核对设备、OS、Agent、项目和 token。对比相同工作空间、时间范围、时区与 token 口径的数据库记录；不能拿历史总量和今日量直接比较。其他页面使用同一云端快照。

点击“刷新”：本机 Rust 立即采集并上传，然后重新读取 Supabase；刷新期间按钮显示“刷新中”。并发采集最多等待约 120 秒，失败应查看日志而不是期待 UI 凭空增加数据。Mac 刷新不会远程强制 Windows 立即采集，Windows 仍按自身周期上传。

详细日志位置、事件名和分层对账见 [PIPELINE_LOGS.md](PIPELINE_LOGS.md)。本次安装包验收包括 Mac/Windows 架构检查、ZIP 完整性、SHA-256 和既有 CI 结果；没有声称本次在两台真实 Windows 上完成安装。

## 7. 周期调整、排障和卸载

测试周期保持 1 分钟。后续改 10 分钟时：Mac 重新运行 `install-schedule ... --interval-seconds 600`；Windows 已注册设备重新执行 `install-tokenstep-agent.ps1 -AgentExe <exe路径> -IngestUrl <上传URL> -IntervalMinutes 10`，无需重复消费注册码。上传周期与展示端读云周期是不同设置。

常见原因：注册码过期/已使用、账户未加入 workspace、设备被停用、钥匙串未授权、任务用户错误、来源路径/格式变化、网络/代理不可用。电脑本地采集成功不代表上传必然成功；离线批次保存在 SQLite outbox，恢复后按顺序重试。检查系统代理是否确实运行，不要默认关闭全局代理。

Mac 停用采集：先运行 `launchctl bootout gui/$(id -u)/com.tokenstep.collector`，再退出 App；卸载 App 可移到废纸篓，保留代理状态和凭据以便恢复。Windows 使用随包 `uninstall.cmd` 停止/移除任务；现有脚本保留状态和凭据。若要永久撤销设备，管理员在 Supabase 中核对准确设备 UUID 后停用该设备；卸载电脑程序不会自动删除云端历史数据。
