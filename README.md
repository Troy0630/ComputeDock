# ComputeDock

[English](README_EN.md) · [Apache-2.0](LICENSE)

原生 macOS 服务器算力监控 App。界面参考 [RackTop](https://github.com/Tongzh-SEU/RackTop) 的多机卡片总览，使用 SwiftUI 独立实现，聚焦 CPU、显存与 GPU 进程。

## 直接试用

当前打包版本适用于 **Apple Silicon Mac，macOS 14 或更高版本**。首次打开会展示明确标注的模拟数据。仓库提供完整源码，可以按下方步骤构建 App；已发布的安装包以 [Releases](https://github.com/Troy0630/ComputeDock/releases) 为准。如果取得 `ComputeDock-macOS-arm64.zip`，解压后打开 `ComputeDock.app`，也可以将它拖入“应用程序”。

这是本地开发版本，使用 ad-hoc 签名，尚未进行 Apple 公证。若在另一台 Mac 上遇到来源限制，可在确认文件来源后通过系统“隐私与安全性”允许打开，或自行从源码构建。

## 连接服务器

1. 确认远端是 Linux，安装有 **Python 3**。NVIDIA 指标还需要可运行的 **nvidia-smi**。无需安装额外 Python 库或常驻服务。
2. 首次连接先在终端运行 `ssh 用户@服务器`，核验主机指纹并完成一次登录。已有有效 `known_hosts` 记录时无需重复。App 不自动接受未知指纹；指纹变化时也会拒绝连接。
3. 点击“添加服务器”，填写名称、主机或 SSH 别名。用户、端口留空时沿用系统 SSH 配置。
4. 选择“密码登录”并输入密码，或选择“SSH 密钥 / Agent”。加密私钥请先通过 `ssh-add` 加入 Agent；也可选择私钥文件。
5. 点击“保存并连接”。默认每 3 秒采样，可切换为 1、3、5 或 10 秒。

密码只保存在本次 App 会话内，退出后不会保留。重启 App 后，在对应服务器详情中点击“输入密码连接”。重新连接也可以重新输入密码。

App 复用 OpenSSH 的 `~/.ssh/config`，包括 HostName、User、IdentityFile 和 ProxyJump。表单中的别名菜单列出主配置文件中的明确 Host 别名；Include 中的别名可以直接输入。**跳板机需要使用密钥或 SSH Agent 认证**，目标服务器的密码不会交给跳板机。当前不支持验证码、二次认证或多步交互登录。

## 功能

- 多服务器卡片总览：CPU 占用、GPU 数量、每张卡的显存与 GPU 利用率。
- 单机详情：系统内存、GPU 温度与功耗、最近 120 次采样的资源趋势。
- GPU 进程：PID、GPU 编号、用户、计算/图形类型、显存、CPU 与完整命令；支持搜索、显存/PID 排序和复制命令。
- 空闲算力：筛选 GPU 利用率低于 10%、显存占用低于 10%，且没有 GPU 进程的卡。
- 暂停/恢复监控、重新连接、编辑和移除连接配置。
- 明确显示演示、连接中、在线、离线和暂停状态；断线时标注保留的数据。

总览的 GPU 数量、可用显存与平均 CPU 来自当前在线服务器；暂停时保留已有采样。平均 CPU 是各服务器百分比的简单平均，未按核心数加权。空闲筛选仅根据当前采样，不能预订或锁定 GPU。

## 指标口径

- 系统 CPU：相邻两次 `/proc/stat` 采样的差值，范围为 0–100%，包括全部 CPU 核心。首次采样显示 `—`。
- 进程 CPU：相邻两次 `/proc/<PID>/stat` 的差值，按单核 100% 计，多线程进程可能超过 100%。首次采样或进程退出时可能显示 `—`。
- 系统已用内存：`MemTotal - MemAvailable`，不把可回收缓存简单视为已用。
- 显存：MiB 转换为 GiB；显存占用与 GPU 利用率分别显示。
- GPU：通过 `nvidia-smi -q -x` 获取，驱动不支持的指标显示 `—`。没有 NVIDIA 驱动时仍能采集 CPU 与系统内存。
- GPU 进程按 GPU 分行，一个进程使用多张卡时会有多条记录。命令和用户名受远端 `/proc` 权限限制。

第一版针对常规 NVIDIA GPU 服务器。MIG/vGPU 的特殊统计、AMD GPU、macOS/Windows 远端、历史落盘、通知、进程结束和训练任务管理均未实现。

## 数据与连接

连接配置保存在本机 `~/Library/Application Support/ComputeDock/servers.json`，仅包含名称、地址、用户名、端口、认证方式和私钥路径，不包含密码或私钥内容。趋势只保存在内存中。

密码经私有临时 Unix socket 交给 SSH 的 AskPass 组件，不放入命令行参数、环境变量值或配置文件；连接结束后清理 socket。采集脚本通过 SSH 在远端 Python 内存中执行，读取 `/proc` 和 `nvidia-smi`，不写远端文件，不需要 sudo。

## 从源码构建

需要 macOS 14+、Apple Command Line Tools 或 Xcode、Swift 5.9+、系统 OpenSSH 与 Python 3。无第三方包依赖。

```bash
git clone https://github.com/Troy0630/ComputeDock.git
cd ComputeDock
./build.sh
open ../ComputeDock.app
```

`build.sh` 默认将构建缓存放到项目的 `.build-local/`，输出 App 到项目的上一级。可通过 `COMPUTEDOCK_BUILD_ROOT` 指定缓存目录，或将输出 App 路径作为第一个参数传入。

```bash
./test.sh
```

测试涵盖 SSH 参数和输入校验、缺失指标解码、密码通道及跳板机密码隔离、CPU 差值、内存口径、GPU XML 的计算/图形进程解析。测试脚本包含不依赖 XCTest 的运行器，可用于只有 Command Line Tools 的环境；有完整 Xcode 时也可运行 `swift test`。

## 验证状态

已完成本机 Release 构建、App 签名完整性检查、6 项 Swift 模型/认证测试及 5 项 Python 解析测试，并检查演示界面、趋势、暂停/恢复、进程搜索和密码表单。Linux 现场采样测试在本机 macOS 上跳过。**尚未使用真实服务器验证连接和 GPU 采样**，需要填入你的服务器信息后联调。

技术参考：[Apple SwiftUI](https://developer.apple.com/documentation/swiftui)、[NVIDIA nvidia-smi](https://docs.nvidia.com/deploy/nvidia-smi/index.html)。

## 贡献

欢迎提交 Issue 和 Pull Request。请先阅读 [贡献说明](CONTRIBUTING.md)，报告问题时移除服务器地址、用户名、密钥、密码和敏感命令参数。GitHub Actions 会检查 macOS 构建与测试，以及 Linux 采集器测试。

## 许可证

Copyright 2026 Troy0630。项目采用 [Apache License 2.0](LICENSE)，版权声明见 [NOTICE](NOTICE)。RackTop 是界面布局的参考项目；本仓库的 SwiftUI 实现、采集器和图标为独立实现。
