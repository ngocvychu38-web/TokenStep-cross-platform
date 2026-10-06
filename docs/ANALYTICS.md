# TokenStep 统计方案

TokenStep 默认是 local-first 工具，不上传 token 数、代码、prompt 或对话正文。

## GitHub 下载统计

GitHub Release asset 自带 `download_count`。它适合看公开下载热度，但不等于真实安装数或日活。

运行：

```bash
python3 script/github_download_stats.py
```

只看最新 5 个版本：

```bash
python3 script/github_download_stats.py --limit 5
```

导出 JSON：

```bash
python3 script/github_download_stats.py --format json
```

导出 CSV：

```bash
python3 script/github_download_stats.py --format csv > tokenstep-downloads.csv
```

可以看到：

- 每个版本的 DMG 下载数
- 每个版本的 ZIP 下载数
- 每个版本总下载数
- 全部版本累计下载数

看不到：

- 真实安装数
- 是否打开过 App
- 日活、周活、月活
- 留存

## 匿名心跳：Aptabase

如果要看安装、日活、版本分布，建议接 Aptabase。

需要先做两件事：

1. 在 Aptabase 创建 TokenStep 项目。
2. 拿到项目的 App Key。

接入后，TokenStep 每天最多发送一次匿名心跳，例如：

```json
{
  "event": "app_heartbeat",
  "version": "0.1.12",
  "os": "macOS"
}
```

原则：

- 使用随机匿名安装 ID。
- 每天最多上报一次。
- 不上传 token 数。
- 不上传代码、prompt 或对话正文。
- 设置里提供开关和隐私说明。

数据查看位置：Aptabase 项目的 Web Dashboard。
