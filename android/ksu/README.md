# Geph5 KernelSU 模块

## 简介
Geph5 翻墙 VPN/代理的 KernelSU 模块打包。开机后以 root 身份运行 `geph5 manager`，
自动管理连接状态。

## 要求
- KernelSU（或兼容的 Magisk / APatch）
- arm64-v8a 架构，Android 7.0+
- 已 root

## 安装
1. 在 KernelSU 管理器中进入「模块 → 从本地安装」，选择模块 zip，安装后重启设备。
2. 或在仓库根目录用 adb 执行 `./android/install.sh <zip>`。

## 使用
- 重启后在 KernelSU 管理器中点击该模块的「操作」按钮即可切换连接（连接/断开）。
- Termux 中安装 gephctl（见 android/termux-gephctl.sh）可获得完整控制：
  `gephctl status / connect / disconnect` 等。
- 也可直接以 su 运行 CLI：`su -c "/data/adb/modules/geph5/geph5 status"`。

## 数据与日志
- 工作目录：/data/adb/geph5（设置 settings.json、控制 socket control.sock、运行时
  socket run/…）
- 管理器日志：/data/adb/geph5/logs/manager.log

## 注意事项
- 全隧道 VPN 模式依赖 `ip`/`nft`；Android 系统无 `nft`，因此 nftables 断网保护
  （kill-switch）相关功能可能不可用。代理（SOCKS5/HTTP）模式完全支持。
- 首次使用需先登录（`geph5 login` / `gephctl login`）后才能连接。

## 卸载
在 KernelSU 管理器中移除模块即可。卸载脚本会停止管理器并删除 /data/adb/geph5
下的全部数据。

## 自行构建 zip
在仓库根目录执行 `./android/build-module.sh`。

---

# Geph5 KernelSU Module

## Overview
A KernelSU module packaging of Geph5, an anti-censorship VPN/proxy. Runs
`geph5 manager` as root at boot to manage the connection automatically.

## Requirements
- KernelSU (or compatible Magisk / APatch)
- arm64-v8a devices, Android 7.0+
- Rooted

## Install
1. KernelSU manager → Modules → Install from storage → pick the zip → reboot.
2. Or from the repo: `./android/install.sh <zip>` (requires adb).

## Usage
- After reboot, tap the module's action button in the KernelSU manager to toggle the
  connection.
- For full control, install gephctl in Termux (see android/termux-gephctl.sh):
  `gephctl status / connect / disconnect`, etc.
- Or run the CLI directly via su: `su -c "/data/adb/modules/geph5/geph5 status"`.

## Data & Logs
- Working dir: /data/adb/geph5 (settings.json, control socket control.sock, runtime
  sockets run/...)
- Manager log: /data/adb/geph5/logs/manager.log

## Caveats
- Full-tunnel VPN mode relies on `ip`/`nft`; Android lacks `nft`, so the nftables
  kill-switch parts may be unavailable. Proxy (SOCKS5/HTTP) mode is fully supported.
- You must log in once before you can connect.

## Uninstall
Remove the module in the KernelSU manager. The uninstall script stops the manager and
deletes /data/adb/geph5 entirely.

## Build your own zip
Run `./android/build-module.sh` from the repo root.
