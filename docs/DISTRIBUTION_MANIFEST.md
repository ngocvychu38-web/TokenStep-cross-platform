# 安装包交付清单

交付日期：2026-10-11。内部测试包，未做 Apple 公证或 Windows Authenticode 签名。完整步骤见 [安装部署](DEPLOYMENT_GUIDE.md)。

| 文件 | 对象 | 内容 |
|---|---|---|
| `TokenStep-0.2.0-macOS-Intel.zip` | Intel Mac / macOS 14+ | SwiftUI App 0.2.0、Rust 代理 0.1.0、公开后端参数配置脚本、安装说明、内部校验表 |
| `TokenStep-Agent-0.1.0-windows-x64.zip` | Windows x64 | Rust 代理、安装/卸载脚本、公开上传及注册地址、校验表；没有 Windows GUI |
| `TokenStep-2026-10-11-delivery.zip` | 整套交付 | 上述两个 ZIP、架构与部署文档、Supabase 迁移/函数源文件、校验表 |

## 代码来源与验证范围

- 私有仓库：`ngocvychu38-web/TokenStep-cross-platform`，分支 `codex/rust-cross-platform`。
- 本次二进制基线：`dc3cf7ca11a7cd5835a2f9d87064587948bf4ca5`。最近功能提交为 `a1a4f2a12d4048918f255a72c7045d607701408e`（立即采集上传再刷新）；两者间仅文档变更。
- Mac App 为本机现有已验证 Intel 构建；代理本次重新执行 `cargo build --release -p tokenstep-agent`。打包前核对两个文件均为 Mach-O x86_64。
- Windows 来自 [成功 CI 运行 38112814846](https://github.com/ngocvychu38-web/TokenStep-cross-platform/actions/runs/38112814846)，源提交 `a1a4f2a`；属于该功能基线，不是上游原版安装包。ZIP 内校验表另行核验。
- 安装包完整性及文件架构可在 Mac 验证；Windows 真实设备安装、权限和各工具格式对账由各台设备独立验收。未把 CI 成功写成真实 Windows 全场景安装成功。

## 固定文件校验值

```text
c45473c7342d7dd5621ff65b5d44072c9bb5519d942480a97d010ab4302d1f03  Mac tokenstep-agent
2d527e1eb33491c6b3ae9dfabb0acc2369dfd7866f778736051015924f82bec4  Mac TokenStep.app/Contents/MacOS/TokenStepSwift
e32c5e242e71bd5435b7def81479adf38655689735753bc045d1252bdc68169c  TokenStep-Agent-0.1.0-windows-x64.zip
```

Mac ZIP 及整套 ZIP 的归档校验以交付旁边生成的 `SHA256SUMS.txt` 为准。归档封装时间可能改变 ZIP 哈希，不改变上述固定二进制校验值。

Mac 在交付目录执行 `shasum -a 256 -c SHA256SUMS.txt`；在解压的 Mac 子目录也执行同一命令验证内部文件。Windows 用 PowerShell `Get-FileHash .\TokenStep-Agent-0.1.0-windows-x64.zip -Algorithm SHA256` 对照上述归档值；安装器另检查 exe 哈希。

打包流程：先按架构文档构建 Intel App 和代理，下载上述 Windows CI 安装器 artifact，再执行 `script/package_internal_delivery.sh <新输出目录> <Windows ZIP绝对路径>`。仅复制指定文档、迁移与函数，不复制本地状态、日志、凭据或 Supabase `.temp`。配置脚本仅预置公开项目 URL/Publishable Key；新设备必须自己注册，前端用户必须自己登录。
