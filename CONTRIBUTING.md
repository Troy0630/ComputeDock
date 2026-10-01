# 贡献说明

欢迎通过 Issue 报告问题或建议，通过 Pull Request 提交改进。

## 开发

需要 macOS 14+、Apple Command Line Tools 或 Xcode、Swift 5.9+、Python 3 和系统 OpenSSH。项目没有第三方包依赖。

```bash
./test.sh
./build.sh
open ../ComputeDock.app
```

在 Linux 上可单独测试采集器：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

## 提交改动

- 说明解决的问题、最终行为以及验证方式。
- 修改采集解析或认证时，请覆盖缺失指标、进程退出、连接失败等边界情况。
- 不要提交构建缓存、安装包、个人 SSH 配置、服务器连接配置或凭据。
- 界面改动可附演示模式截图；真实环境截图和日志请先删除敏感信息。
- 保持监控只读，避免在连接时修改远端文件或自动接受服务器指纹。

提交的贡献沿用本项目的 Apache-2.0 许可证。
