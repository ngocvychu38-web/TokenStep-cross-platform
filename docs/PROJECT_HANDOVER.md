# TokenStep 项目交付总览

更新日期：2026-10-11。本文档面向项目使用、部署和后续开发；描述的是 `codex/rust-cross-platform`，不是上游原版的纯本地模式。

## 阅读顺序

1. [功能与技术架构](PROJECT_OVERVIEW.md)：产品能力、模块关系、Token 采集口径、数据模型和限制。
2. [安装部署指南](DEPLOYMENT_GUIDE.md)：Intel Mac、Windows x64、现有 Supabase 与新后端的部署步骤，独立验证和卸载。
3. [安装包清单](DISTRIBUTION_MANIFEST.md)：实际交付文件、平台、代码来源及 SHA-256。
4. [日志与对账](PIPELINE_LOGS.md)：定位采集、上传、服务端入库及前端读取问题。

## 当前交付边界

- Mac：原生 SwiftUI 展示应用 + 独立 Rust 采集代理。
- Windows：Rust 后台采集代理、PowerShell 安装器和任务调度；没有 Windows GUI。
- Supabase：设备注册、用量入库、工作空间授权及查询；不是远程读取电脑文件的服务。
- 数据展示的唯一来源为 Supabase；原始日志留在各设备。
- 后台任务测试间隔为 1 分钟；生产间隔建议按已有需求改为 10 分钟，本文不会自动修改现有任务。
- 安装包属于内部测试交付，未提供 Developer ID 公证或 Windows Authenticode 发布签名。

所有安装包均不包含真实账号密码、上传凭据、聊天记录、本机快照或 Supabase service-role key。公开项目地址和 Publishable Key 可预置；登录及每台设备注册必须分别完成。
