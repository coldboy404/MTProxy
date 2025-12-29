# MTProxy Go/Python 一键安装脚本 (支持ipv6)

> 基于 9seconds/mtg (Go版本) 和alexbers/mtprotoproxy（Python版本）的高性能 MTProto 代理一键部署工具（支持导出ipv6链接）。

[![Shell](https://img.shields.io/badge/Language-Shell-blue.svg)](https://github.com/weaponchiang/MTProxy)
[![OS](https://img.shields.io/badge/OS-CentOS%20%7C%20Debian%20%7C%20Ubuntu%20%7C%20Alpine-success.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

这是一个轻量级、智能化的 MTProxy 安装脚本。它会自动检测并下载 GitHub 上最新的 `mtg` 内核，支持主流 Linux 发行版（包括 Alpine），并内置了 FakeTLS 伪装功能。

## ‼️免责声明‼️

1.本项目仅供学习与技术交流，请在下载后 24 小时内删除，禁止用于商业或非法目的。

2.使用本脚本所搭建的服务，请严格遵守部署服务器所在地、服务提供商和用户所在国家/地区的相关法律法规。

3.对于任何因不当使用本脚本而导致的法律纠纷或后果，脚本作者及维护者概不负责。

----------------------------

## 📥 一键安装

在你的服务器终端（SSH）中执行以下命令即可：

```markdown
bash <(curl -LfsS https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh)
```
### 🚀 快捷管理

安装完成后，你可以随时在终端输入以下快捷命令来调出管理菜单：

```bash
mtp


## ✨ 功能特性

* **🚀 始终最新**：自动通过 GitHub API 获取最新版 `mtg` 内核，拒绝旧版本。
* **🛡️ 强力抗封**：默认配置 **FakeTLS** 模式（伪装成大厂域名），有效对抗干扰。
* **🐧 多系统支持**：完美支持 CentOS 7+, Debian 8+, Ubuntu 16+, Alpine Linux。
* **🔧 极简管理**：提供简单的交互式菜单，支持安装、卸载、重启和查看连接信息。

## 📖 使用指南
​脚本运行后将显示如下菜单：
MTProxy 一键管理脚本
----------------------------
1. 安装 / 重置 MTProxy
2. 修改 端口或域名
3. 查看 链接信息
4. 更新 管理脚本
5. 重启 服务
6. 停止 服务
7. 卸载 MTProxy
0. 退出

---

### 🤝 鸣谢

本脚本的顺利运行离不开以下优秀开源项目的支持：

* **Go 版核心：** [9seconds/mtg](https://github.com/9seconds/mtg) (高性能、低内存占用的完美实现)
* **Python 版核心：** [alexbers/mtprotoproxy](https://github.com/alexbers/mtprotoproxy) (协议支持极佳的经典之作)
* **逻辑参考：** 感谢 [ellermister/mtproxy](https://github.com/ellermister/mtproxy) 提供的优秀配置与安装思路。

---

​