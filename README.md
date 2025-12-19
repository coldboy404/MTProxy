# MTProxy Go 一键安装脚本 (Optimized Edition)

> 基于 9seconds/mtg (Go版本) 的高性能 MTProto 代理一键部署工具。

[![Shell](https://img.shields.io/badge/Language-Shell-blue.svg)](https://github.com/weaponchiang/MTProxy)
[![OS](https://img.shields.io/badge/OS-CentOS%20%7C%20Debian%20%7C%20Ubuntu%20%7C%20Alpine-success.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

这是一个轻量级、智能化的 MTProxy 安装脚本。它会自动检测并下载 GitHub 上最新的 `mtg` 内核，支持主流 Linux 发行版（包括 Alpine），并内置了 FakeTLS 伪装和 BBR 加速开启功能。

## ✨ 功能特性

* **🚀 始终最新**：自动通过 GitHub API 获取最新版 `mtg` 内核，拒绝旧版本。
* **🛡️ 强力抗封**：默认配置 **FakeTLS** 模式（伪装成大厂域名），有效对抗干扰。
* **🐧 多系统支持**：完美支持 CentOS 7+, Debian 8+, Ubuntu 16+, Alpine Linux。
* **⚡ BBR 加速**：内置一键开启 BBR 拥塞控制，提升网络吞吐量。
* **🔧 极简管理**：提供简单的交互式菜单，支持安装、卸载、重启和查看连接信息。

## 📥 一键安装

在你的服务器终端（SSH）中执行以下命令即可：

```bash
bash <(curl -LfsS [https://raw.githubusercontent.com/weaponchiang/MTProxy/refs/heads/main/mtp.sh](https://raw.githubusercontent.com/weaponchiang/MTProxy/refs/heads/main/mtp.sh))

预览界面⬇️
MTProxy (Go版) 一键管理脚本
----------------------------
1. 安装 / 重置配置   <-- 首次运行选这个
2. 查看 链接信息     <-- 获取分享给 TG 的链接
3. 开启 BBR 加速     <-- 优化网络速度
4. 停止 服务
5. 重启 服务
6. 卸载 MTProxy
0. 退出
----------------------------
