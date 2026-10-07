# 采集 → Supabase → 前端日志

## 三层日志位置

| 层 | 位置 | 关键记录 |
| --- | --- | --- |
| 本机 Rust 采集上传 | ~/Library/Application Support/TokenStep/agent/logs/agent.log、agent-error.log | collection_ok：桶数、Token 合计、耗时；source_result：Agent 状态、文件数、记录数；credential_read_started/ok；upload_started/response；batch_acknowledged；cycle_ok |
| Supabase | Dashboard → Edge Functions → ingest-usage → Logs/Invocations；SQL ingestion_runs | ingest_ok/ingest_response：请求 UUID、HTTP 状态、耗时、已鉴权设备 UUID、桶数、接受数和重复标记；数据库持久化入库时间及采集时间 |
| SwiftUI 读取 | ~/Library/Application Support/TokenStep/logs/lifecycle.log | cloud_sign_in、cloud_refresh、cloud_http_started/http（端点、状态、字节数、服务端请求 UUID、耗时）、cloud_snapshot_applied（行数、Token 合计、设备数、来源数） |

前端日志记录共享 AppState 数据应用成功，不等同于证明每个像素已经渲染。今日、历史、统计、Agent 工作强度和浮层使用同一快照；不存在各页独立采集。

本机后台日志中的 request_id 与 Edge 自定义日志 request_id 对应；前端 sb-request-id 对应 Supabase API 网关请求。采集生成时间 generated_at 可与 ingestion_runs 对账。HTTP 200 仍需确认 accepted 应答及本地 queue ack，不能仅凭请求发出判定成功。

## 安全约定

不记录密码、Bearer Token、API Key、请求/响应原文、对话或项目路径。前端错误只记录安全类别；来源信息仅使用既有 SourceDiagnostic 安全字段。前端 lifecycle.log 超过约 512KB 会按既有机制清理；代理 stdout 文件目前无自动轮转，长时间运行应管理日志大小。

## 独立检查

```bash
tail -n 40 "$HOME/Library/Application Support/TokenStep/agent/logs/agent.log"
tail -n 40 "$HOME/Library/Application Support/TokenStep/logs/lifecycle.log"
```

```sql
select generated_at, created_at, bucket_count, source_count, status
from public.ingestion_runs order by created_at desc limit 10;
select agent_key, state, files, records, last_attempted_at, last_succeeded_at
from public.source_sync_status order by agent_key;
select count(*) as rows, sum(total_tokens) as tokens
from public.usage_dashboard;
```

前端登录后预期依次出现 cloud_sign_in_ok、两个 REST 端点 HTTP 200（含分页）、cloud_snapshot_applied。空数据仍可成功，不应将行数 0 等同于失败。刷新失败出现 cloud_refresh_failed，保留最后成功快照。缺少当前版本日志时，不能据此声称已经读取。

运行 `./script/test_cloud_snapshot.sh` 会用隔离 UserDefaults 和 URLProtocol 验证成功/失败读取、快照应用及日志凭据不泄露；不接触真实用户密码，也不代替正式 UI 登录验收。

## 本次检查（2026-10-07）

旧代理连续周期上传与数据库入库匹配；截至 08:22:20（北京时间）每次 362 桶、11 个来源。云端包含 Codex、Claude Code、TeleAgent 用量；missing 表示本机未发现该来源，不是上传失败。新版记录 Codex 301 文件/19470 记录、Claude Code 5 文件/181 记录、TeleAgent 1 文件/6761 记录。WorkBuddy 为 missing_valid_rows，其余未安装来源 missing。

此前可找到 07:55:23–24 前端 GET usage_dashboard 的 HTTP 200，但这属于旧版本记录；当前页面读数必须在日志增强版登录后重新确认。Edge v3 日志已部署并用未授权请求验证 401 与请求 UUID 日志；新版代理采集成功，首次读取钥匙串等待新二进制授权。安装新版前端会结束进程内会话，用户需重新登录。

08:25:43 已完成一轮日志对账：本机 upload_response HTTP 200、accepted=362；云端 ingest_ok/ingest_response 同一请求编号 b8e3e2e1-b40d-415f-b732-efab603e33a1，数据库 created_at=00:25:43.309204Z。08:26:16 日志增强版前端已启动，cloud_store_initialized authenticated=false，等待正式账号重新登录。Rust 测试、clippy、云端 SQL fixture、Swift 云端转换/读取日志 fixture 和 Intel 完整构建通过；完整 SwiftPM 测试仍受本机缺少 XCTest 限制。
