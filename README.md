# Geph5 Android Module

Geph5 作为 Android 系统模块（KernelSU / Magisk / APatch）运行，开机以 root 身份启动
`geph5 manager` 守护进程，并自动管理连接状态。

Geph5 是一个防审查 VPN/代理客户端。相比 Geph4 是一次重大重写，架构上做了大幅简化和清理。

## 快速开始

### 构建模块 zip（arm64 + x64）

```bash
./android/build-module.sh            # 构建两个架构
./android/build-module.sh --arch arm64   # 只构建 arm64
./android/build-module.sh --skip-build   # 复用已有二进制，只重打包
```

产物在 `android/dist/geph5-ksu-v0.3.9-{arm64,x64}.zip`。

### 安装（三种方式）

1. **Root 管理器「从本地安装」**：KernelSU / Magisk / APatch 的模块页面选择对应架构 zip，
   安装后重启。
2. **ADB 一键安装**（自动探测 ksud / magisk / apd）：

   ```bash
   ./android/install.sh android/dist/geph5-ksu-v0.3.9-arm64.zip
   ```

3. **Magisk**：`adb push ... /data/local/tmp/ && adb shell su -c 'magisk --install-module /data/local/tmp/geph5-ksu.zip'`

刷入模块时会**自动部署 `gephctl` 控制脚本**：若检测到 Termux 则装进
`$PREFIX/bin/gephctl`，否则回退到 `/data/local/tmp/gephctl`。

### 使用

重启后 `service.sh` 自动以 root 启动 manager。三种控制方式任选其一：

- **Termux 里用 `gephctl`**（薄壳，直接透传 geph5 子命令，不用写 `su -c`）：

  ```bash
  gephctl status                                    # 管理器 + 连接状态
  gephctl connect / disconnect                      # 连接 / 断开
  gephctl exit-constraint set --country us          # 设出口
  gephctl vpn on | proxy on                         # VPN / 代理模式
  gephctl logs -n 50                                # 引擎日志
  gephctl start / stop / restart                    # 服务生命周期
  gephctl login
  ```

- **CLI（su）**：`su -c "/data/adb/modules/geph5/geph5 status"`
- **管理器操作按钮**：KernelSU / Magisk / APatch 模块页的「操作」按钮切换连接。

完整说明见 [android/ksu/README.md](android/ksu/README.md)。

## 数据与日志

- 工作目录：`/data/adb/geph5`（设置 `settings.json`、控制 socket `control.sock`、运行文件 `run/`）
- 管理器日志：`/data/adb/geph5/logs/manager.log`

## 说明

- 全隧道 VPN 依赖 `ip`/`nft`；Android 无 `nft`，故 nftables kill-switch 不可用。
  代理（SOCKS5/HTTP）+ 自动代理模式完全支持。
- 首次使用需 `gephctl login` 登录后才能连接。
- `register-manager` 仅桌面平台有效（systemd/launchd/计划任务），Android 上会报错；
  本模块开机自启由 `service.sh` 负责。

---

# Geph5

Geph5 相比 Geph4 的核心架构差异：

## Overview

- 不再使用 `sosistab2` 等基于不可靠链路的可靠传输；混淆传输自身须提供可靠传输。
  实际上基于 TCP 上的流复用，而非包/UDP。
- 客户端不再有复杂的智能热切换管道逻辑；一个 session 用至断开再另起一个。
  session 创建足够快时，唯一可见差异是代理 TCP 连接会重置，多数应用可优雅处理。
- 中央认证服务器称为 **broker**（而非 binder），使用无端到端加密的 JSON-RPC API，
  对完整性关键的响应带 ed25519 签名。
- broker 负责与 bridge / exit 通信以建立路由，消除了 `(bridge 数) × (exit 数)`
  的复杂通信模式。
- VPN 模式通过流（socks5）模式隧道实现，但支持 tun2socks 风格的流量拦截。
- 普遍使用配置文件而非大量命令行参数。
- GUI 客户端用 Rust 编写直接调用协议库，不再使用 webview。

## License

代码一般以 **MPL 2.0** 授权。对各类项目广泛有用的底层库（如 `sillad`）一般以
ISC 授权。

## Code organization

Geph5 采用 Cargo workspace（monorepo）组织：

- `libraries/`：库 crate，可互相依赖，均发布到 crates.io。
- `binaries/`：二进制 crate。
  - `geph5-client`
  - `geph5-exit`
  - `geph5-bridge`
  - `geph5-broker`
- `android/`：Android 系统模块（构建、安装、Termux 控制脚本、service.sh 自启）。
