# 云端展示迁移与定时上传验收

2026-10-07：今日、历史、统计、Agent 工作强度（含 TeleAgent）、浮层和分享卡使用同一个 SupabaseCloudStore / CloudSnapshotAdapter。多设备页保留设备、系统、Agent、模型、项目维度；汇总页合并工作空间内所有设备。项目汇总按显示名称合并，精确项目标识见多设备页。

客户端登录凭据仅在进程内存，重新启动需要重新登录。未登录不加载旧本地快照。已登录每 60 秒刷新云端；请求失败保留最后成功数据，退出登录清空。上传新增可选 hourly_usage，旧数据没有小时信息时保留未归属时段 Token，不编造活跃时段。金额、调用次数和完整缓存覆盖率暂无权威来源，显示不可用。

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

启动 `/Applications/TokenStep.app`，用正式邮箱登录。打开今日、历史、统计、Agent 工作强度及多设备页；同一天同 Agent 的 Token 合计应一致。关闭前端后等两分钟，SQL 中仍应出现上传记录。再次启动需登录。退出登录应清空各页面；网络断开后的刷新应提示失败并保留最后云端数据。

真实密码登录及可视交互验收由用户完成；代码编译和合成快照测试不代替此项。

## 4. 后续改为十分钟（目前不执行）

```bash
"/Users/macforai/Library/Application Support/TokenStep/agent/bin/tokenstep-agent" install-schedule \
  --ingest-url https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage \
  --interval-seconds 600
```

此命令重新安装同一任务，不创建重复任务。确认 launchctl 中 interval = 600。Windows 安装脚本的 `-IntervalMinutes` 当前默认 1，正式期传 10；Windows 实机安装与对账仍待完成。
