TokenStep Windows x64 后台采集器 0.1.0

适用：Windows 10/11 x64，使用 Windows PowerShell 5.1，无需安装 Rust。
本包提供后台采集与云端上传；当前无 Windows 图形仪表盘。
上传后可在已登录同一工作空间的 Mac TokenStep 云端页面查看 Windows 设备。

安装
1. 将 ZIP 完整解压到一个文件夹，不能直接在 ZIP 内运行。
2. 先获取你的工作空间的一次性设备注册码（10 分钟有效，只能使用一次）。
   在 Supabase SQL Editor 执行：
   select public.create_device_enrollment_code('e59b5c17-4065-4b8b-8214-ecb3e0e72181');
   此注册码只用于该 TokenStep 工作空间；不要把它公开或发给其他人。
3. 双击 install.cmd，以日常运行 Codex/Claude Code 的 Windows 用户执行。
4. 输入注册码。脚本检查校验和及 Windows 凭据管理器、注册设备、安装计划任务。
5. 首次采集会立即在后台启动。后续以一分钟为测试间隔，实际完成时间包含采集与网络耗时。

安装位置：%LOCALAPPDATA%\TokenStep\Agent\bin\tokenstep-agent.exe
数据位置：%LOCALAPPDATA%\TokenStep\agent
日志位置：数据位置下 logs\agent.log 和 logs\agent-error.log
计划任务：TokenStep Agent，以当前登录用户身份运行，用户退出登录后暂停。
设备上传凭据保存在 Windows Credential Manager，不写入安装包或明文文件。

验证（在 PowerShell 中）
Get-ScheduledTask -TaskName 'TokenStep Agent'
Get-Content "$env:LOCALAPPDATA\TokenStep\agent\logs\agent.log" -Tail 40
成功日志应出现 collection_ok、batch_acknowledged、cycle_ok。
还应在 Mac 的“多设备数据”页看到 Windows 设备；仅任务创建成功不代表上传成功。
本包在 Windows CI 构建和测试；真实 Agent 日志、云端上传仍需安装后实机验证。

采集范围
Codex：%USERPROFILE%\.codex\sessions
Claude Code：%USERPROFILE%\.claude\projects
TeleAgent/OpenCode：按用户目录及 LOCALAPPDATA 候选路径发现数据库。
Antigravity（实验）：%USERPROFILE%\.gemini\antigravity\conversations\*.db，只读其中的 token 用量、模型与时间字段，不读对话内容。
仅上传设备、Agent、模型、脱敏项目名称及 Token/小时汇总，不上传聊天正文或代码。
WSL 内的日志不自动发现。金额、调用次数等尚无权威云端字段。

正式期将间隔改为十分钟（在解压目录的 PowerShell 中）
.\install-tokenstep-agent.ps1 -AgentExe .\tokenstep-agent.exe -IngestUrl 'https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage' -IntervalMinutes 10
此命令更新任务，不重新注册设备。

停止/卸载
双击 uninstall.cmd，停止后台任务并移除计划任务，保留数据及凭据以便重装。
如需撤销该设备上传权限，请在云端禁用该设备。

本测试包尚无 Authenticode 发布签名。
