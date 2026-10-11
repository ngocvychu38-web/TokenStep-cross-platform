# 云端展示迁移与定时上传验收

2026-10-07：今日、历史、统计、Agent 工作强度（含 TeleAgent）、浮层和分享卡使用同一个 SupabaseCloudStore / CloudSnapshotAdapter。多设备页保留设备、系统、Agent、模型、项目维度；汇总页合并工作空间内所有设备。项目汇总按显示名称合并，精确项目标识见多设备页。

客户端登录密码按项目和账号保存在 macOS 钥匙串，启动时自动登录；访问令牌和刷新令牌仅在进程内存。主动退出登录删除保存的密码。未登录不加载旧本地快照。已登录每 60 秒刷新云端；请求失败保留最后成功数据，退出登录清空。上传新增可选 hourly_usage，旧数据没有小时信息时保留未归属时段 Token，不编造活跃时段。金额根据云端模型和 Token 分项复用原有 API 列表价规则估算，不代表实际账单；调用次数和完整缓存覆盖率暂无权威来源，显示不可用。

## 1. 独立验证采集及转换

仓库根目录运行 `cargo test --workspace`、`./script/test_cloud_snapshot.sh`。后者验证跨设备汇总、重复行去重、TeleAgent、小时数据和旧版缺失小时字段。

已安装代理及数据目录：`/Users/macforai/Library/Application Support/TokenStep/agent`。`snapshot.json` 为最近本机采集结果，`outbox.sqlite3` 为未确认上传队列；`last-sync.json` 仅在队列全部成功上传后更新。不得将该目录内的凭据导出或上传。

## 2. 验证定时上传

macOS 用户 LaunchAgent：`com.tokenstep.collector`，RunAtLoad、StartInterval=60。退出前端仍运行；机器休眠和退出 macOS 用户登录期间不能运行。一次周期尚未结束时不并发启动另一周期。网络失败留存队列。

运行 `launchctl print gui/501/com.tokenstep.collector` 检查 run interval = 60；查看数据目录 logs/agent.log 中连续的 cycle_started、batch_acknowledged、cycle_ok。第一次读取钥匙串可能需要用户选择“始终允许”，确认前不可判定上传成功。

Supabase SQL Editor：

```sql
select generated_at, created_at, bucket_count,
       created_at - lag(created_at) over(order by created_at) as interval
from public.ingestion_runs
order by created_at desc limit 10;

select agent_key, count(*) as buckets, sum(total_tokens) as tokens,
       count(*) filter(where jsonb_array_length(hourly_usage)>0) as with_hours
from public.usage_dashboard group by agent_key;
```

预期上传记录持续增加，正常周期约一分钟（实际包含采集/网络时间）；数据库中的最新设备快照与本机 snapshot.json 对账。重复快照不会累加消耗。小时汇总只来自有合法时间戳的事实，剩余部分展示未归属。

## 3. 验证展示

启动 `/Applications/TokenStep.app`，用正式邮箱登录。打开今日、历史、统计、Agent 工作强度及多设备页；同一天同 Agent 的 Token 合计应一致。关闭前端后等两分钟，SQL 中仍应出现上传记录。再次启动应自动登录。退出登录应清空各页面；网络断开后的刷新应提示失败并保留最后云端数据。

真实密码登录及可视交互验收由用户完成；代码编译和合成快照测试不代替此项。

### 2026-10-07 运行记录复核

本次只读检查确认正式用户已于北京时间 08:33:58 登录成功。08:46:19 前端两类 REST 端点分页请求均返回 HTTP 200，随后记录 `cloud_snapshot_applied rows=362 total_tokens=2707677955 devices=1 sources=11`。日志中未发现 `cloud_refresh_failed`；该记录证明共享展示数据已应用，逐页像素、过滤器、退出登录和断网交互仍需单独验收。

后台最近十轮成功周期从 08:33:29 持续至 08:46:06，各轮均确认 `accepted=362`。相邻完成时间间隔为 72.0–110.5 秒；LaunchAgent 的 StartInterval 仍为 60 秒，采集与上传耗时会影响实际完成间隔。任务上次退出码为 0，stderr 日志为空。

08:46:04 生成的本机快照通过已安装代理的 `verify`：362 桶、2,707,677,955 Token，全部桶具有小时数据，小时合计与总计一致。Codex 为 2,233,898,418，TeleAgent 为 438,073,126，Claude Code 为 35,706,411。这些值是快照累计量。只读查询 outbox 显示未确认批次为 0，`last-sync.json` 成功时间为 08:46:06；前端 08:46:19 总计与此快照一致。

本次没有重新查询服务端 SQL 或 Edge 日志；最近一轮端到端判断依据为设备 HTTP 成功及 ack、队列清空和正式账号前端云端读取。此前服务端请求编号对账见 [流水线日志](PIPELINE_LOGS.md)。钥匙串授权及正式账号登录已完成，不再作为待办；Windows 实机与 Rust/Swift Codex 口径对账仍未完成。

## 4. 后续改为十分钟（目前不执行）

```bash
"/Users/macforai/Library/Application Support/TokenStep/agent/bin/tokenstep-agent" install-schedule \
  --ingest-url https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage \
  --interval-seconds 600
```

此命令重新安装同一任务，不创建重复任务。确认 launchctl 中 interval = 600。Windows 安装脚本的 `-IntervalMinutes` 当前默认 1，正式期传 10；Windows 实机安装与对账仍待完成。
