# HAOS for LCKFB Taishan Pi — 项目完整资料

> 本文档汇总 `sunshijiang/haos-taishan` 项目的全部技术信息：目标硬件、
> 上游依赖、仓库结构、构建方式、同步机制、验证方法，以及排障过程中
> 踩过的所有坑。
>
> 仓库：<https://github.com/sunshijiang/haos-taishan>

---

## 目录

1. [目标与用途](#1-目标与用途)
2. [硬件规格](#2-硬件规格)
3. [上游依赖与关键事实](#3-上游依赖与关键事实)
4. [仓库结构](#4-仓库结构)
5. [构建方式](#5-构建方式)
6. [同步机制](#6-同步机制)
7. [验证方法](#7-验证方法)
8. [分区与容量策略](#8-分区与容量策略)
9. [1GB 内存约束](#9-1gb-内存约束)
10. [排障记录](#10-排障记录)
11. [待办与人工步骤](#11-待办与人工步骤)

---

## 1. 目标与用途

为立创·泰山派（LCKFB Taishan Pi，RK3566）构建 **Home Assistant
Operating System** 镜像 —— 与官方 HAOS 同源、同构建体系，仅做板级适配。

**用途**：作为家庭自动化主机，只跑 Home Assistant。不含桌面、不含通用包
管理器、不含额外服务，与官方 HAOS Green 的定位一致。

**关键设计决策**：不做完整 fork。上游 `home-assistant/operating-system`
有 500+ 文件且两周一变（内核版本更新），fork 必然长期冲突。本仓库只保留
泰山派定制层，构建时按 `upstream.pin` 拉上游再叠加 —— 上游同步 = 改一行 pin。

---

## 2. 硬件规格

| 项目 | 参数 |
|:-|:-|
| SoC | Rockchip RK3566，4×Cortex-A55 @1.8GHz，Mali-G52 2EE，NPU 1TOPS |
| 内存 | LPDDR4 —— 1GB（当前配置），另有 2/4/8GB 变体 |
| 存储 | eMMC —— 16GB（当前配置），另有 8/32/64/128GB；TF 卡座（最高 512GB） |
| PMIC | Rockchip RK809（I²C0 @ 0x20），含 1W 喇叭 + 麦克风 |
| 网络 | 千兆以太网（GMAC + PHY）+ 板载 2.4GHz WiFi/BT（AP6212） |
| USB | 1× USB 3.0 (Type-A)、2× USB 2.0 (Type-A)、1× Type-C 供电 |
| 存储扩展 | SATA、mini PCIe（39Pin 高速排针）、TF 卡 |
| 显示 | micro-HDMI（4K@60）、EDP、MIPI DSI |
| 其他 | 40Pin GPIO（Raspberry Pi 兼容）、RGB 状态灯、Recovery + Reset 键 |

### 设备树与 U-Boot 现状（重要）

| 项目 | 状态 |
|:-|:-|
| 设备树 | **主线内核已含** `rockchip/rk3566-lckfb-tspi`（stable v6.18.59 同样有），**无需自写 DTS** |
| U-Boot | **主线 v2026.04 已含** `configs/lckfb-tspi-rk3566_defconfig` 与 `dts/upstream/src/arm64/rockchip/rk3566-lckfb-tspi.dts` |

因此实际只需要 **2 个小补丁**：

| 补丁 | 作用 |
|:-|:-|
| `patches/linux/0001-…-enable-eMMC-HS200.patch` | RK356x 的 eMMC 在 DDR52 模式下会写坏数据，只有 HS200 可靠（对齐上游 Green 的 "green: Do not use eMMC DDR52 mode, enable HS200"） |
| `patches/uboot/0001-…-enable-HAOS-required-options.patch` | 主线板级 defconfig 缺 `CMD_PART`/`CMD_FAT`/`CMD_FILEENV`，HAOS 启动脚本需要它们读分区、读 `cmdline.txt`、读设备树 |

### 板级外设要点

| 外设 | 详情 |
|:-|:-|
| RGB LED | gpio1 PB2/PB1/PB0，低有效，含 `leds-group-multicolor` |
| Recovery 键 | SARADC ch0 的 ADC key，内核侧 `CONFIG_KEYBOARD_ADC=m` 才生效 |
| 电源键 | RK809 @ i2c0 0x20，寄存器 0xf0 —— **U-Boot 擦除流程靠它**（与 Green 同款探测） |
| WiFi/BT | AP6212，需 `CONFIG_MMC_SDHCI_SDMA=y` |
| 启动顺序 | `spl-boot-order = "same-as-spl", &sdmmc0, &sdhci` → **TF 卡优先于 eMMC** |

---

## 3. 上游依赖与关键事实

### 上游仓库

| 仓库 | 用途 | 版本 |
|:-|:-|:-|
| `home-assistant/operating-system` | 构建系统（Buildroot 外部树） | pin 在 `upstream.pin` |
| `home-assistant/buildroot` | 真正的构建系统（submodule） | 分支 `2024.02.x-haos` |
| `home-assistant/core` | 容器镜像来源 | 按 `machine` 标签 |

### Supervisor machine 必须是 `green`

Core 容器发布为 `ghcr.io/home-assistant/{machine}-homeassistant`。上游
Core 的构建矩阵**只有**这些 machine：

```
generic-x86-64, khadas-vim3, odroid-c2, odroid-c4, odroid-m1, odroid-n2,
qemuarm-64, qemux86-64, raspberrypi3-64, raspberrypi4-64, raspberrypi5-64,
yellow, green
```

**没有 `taishan`**。自建 machine 意味着要维护 Core 分支并发布到 GHCR。
`green` 是 RK3566 同款 SoC，其 Core 镜像是不含 Green 专有硬件假设的通用
aarch64 Python 运行时，直接可用。

`BR2_PACKAGE_OS_AGENT_BOARD=Supervised`（而非 `Green`）：Green 的 LED 特性
依赖名为 `power`/`activity`/`user` 的三个 LED，泰山派是 `status-rgb`，
用 Green 会导致 LED 调用失败。`Supervised` 不注册板级特性，走通用路径。

### 分区布局（上游 hybrid GPT）

固定分区约 700MB，`hassos-data` **无 size 上限** → 同一镜像适配
8/16/64/128GB 全部 eMMC 变体。详见 [第 8 节](#8-分区与容量策略)。

### 内存与缓存（上游 HAOS 既有行为）

| 项 | 值 |
|:-|:-|
| zram swap | RAM 的 25%（1GB → 256MB） |
| zram var / tmp | 各 32MB |
| swapfile | RAM 的 33%，**下限 1GiB 上限 4GiB**（1GB 板上是 1GiB） |

### Buildroot 并行度

`BR2_JLEVEL` 控制**包内**并发（`package/Makefile.in`）；顶层因 Buildroot
保留 `.NOTPARALLEL` 而串行，以保证可复现性。上游 CI 靠 `actions/cache`
持久化 ccache 提速。

### 内核来源

HAOS 用 stable 树。**Linux 6.18.59 不在 cdn.kernel.org**（该版本由
stable 维护），需用 `git.kernel.org/.../stable/linux.git` 或其 GitHub 镜像
`github.com/gregkh/linux`。

---

## 4. 仓库结构

```
haos-taishan/
├── board/taishan/              # 板级定制层（构建时覆盖到上游对应位置）
│   ├── meta                    # BOARD_ID / SUPERVISOR_MACHINE / 分区参数
│   ├── kernel.config           # 内核配置片段
│   ├── uboot.config            # U-Boot 配置片段
│   ├── uboot-boot.ush          # 启动脚本（Green 版改写）
│   ├── haos-hook.sh            # 首次启动的 hook
│   ├── cmdline.txt             # 内核命令行
│   ├── image-spl-spl.cfg       # SPL 分区布局
│   ├── partition-spl-spl.cfg   # GPT 分区表
│   ├── rockchip-blobs.md       # rkbin blob 版本说明
│   └── patches/
│       ├── linux/0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch
│       └── uboot/0001-configs-lckfb-tspi-rk3566-enable-HAOS-required-options.patch
├── configs/taishan_defconfig  # Buildroot 配置
├── scripts/                    # 同步 / 构建 / 校验
├── docs/                       # 8 篇专题文档
├── upstream.pin                # 上游 pin，<40位 sha> <日期> <标签>
└── .github/workflows/          # build / sync-upstream / alert-build-failure
```

### 关键配置项

| 文件 | 键 | 值 | 原因 |
|:-|:-|:-|:-|
| `configs/taishan_defconfig` | `BR2_LINUX_KERNEL_INTREE_DTS_NAME` | `rockchip/rk3566-lckfb-tspi` | 主线设备树 |
| | `BR2_TARGET_UBOOT_BOARD_DEFCONFIG` | `lckfb-tspi-rk3566` | 主线 U-Boot 板级配置 |
| | `BR2_PACKAGE_HASSIO_MACHINE` | `green` | 见上文 |
| | `BR2_PACKAGE_OS_AGENT_BOARD` | `Supervised` | 见上文 |
| | `BR2_GLOBAL_PATCH_DIR` | `$(BR2_EXTERNAL_HAOS_PATH)/patches $(BR2_EXTERNAL_HAOS_PATH)/board/taishan/patches` | 上游 + 板级补丁 |
| | `BR2_DL_DIR` / `BR2_CCACHE_DIR` | `/cache/dl` `/cache/cc` | 容器挂载点约定，原生构建需手动准备 |
| | `BR2_ENABLE_LTO` | `y` | 与上游一致 |
| `board/taishan/meta` | `PARTITION_TABLE_TYPE` | `hybrid` | Rockchip SPL 兼容 |
| | `BOOT_ENV_SIZE` | `0x8000` | 与 U-Boot 环境区一致 |
| | `SUPERVISOR_ARCH` | `aarch64` | — |

---

## 5. 构建方式

### 方式 A：GitHub Actions（推荐用于正式产出）

| 工作流 | 触发 | 产物 |
|:-|:-|:-|
| `build.yml` | push 到 main（board/configs/scripts/upstream.pin 变更）、手动、定时（每周日 03:17 UTC） | `haos_taishan-*.img.xz`、`haos_taishan-*.raucb` |
| `sync-upstream.yml` | 每日 04:23 UTC、手动 | 更新 `upstream.pin` 的 PR |
| `alert-build-failure.yml` | Build 失败时 | GitHub Issue + 推送通知 |

### 方式 B：WSL2 原生构建（推荐用于本地迭代）

**不需要 Docker。** Buildroot 自己编译工具链，宿主只需普通 Linux userland；
上游的 `install_tini_docker` 只是建 `docker-init → tini` 符号链接，
Core 镜像用 `skopeo` 从 GHCR 拉，全程不需要 Docker daemon。

```bash
# 从 Windows 执行
bash scripts/wsl-run.sh              # 完整流程
bash scripts/wsl-run.sh --jobs 8     # 指定并发
```

或分步（WSL2 内）：

```bash
cd /mnt/e/sun/TSP/haos-taishan
bash scripts/wsl-setup.sh      # 装依赖
bash scripts/wsl-build.sh      # 构建
bash scripts/wsl-prefetch.sh   # 预取失效上游站点的源码
```

**构建放在 WSL2 的 ext4 里**，不在 `/mnt/e`：
- `/mnt/e` 走 Windows 转换层，比 ext4 慢数倍，而 Buildroot 有海量小文件操作
- 上游有两个文件名含字面 `\x2d`（如
  `buildroot-external/rootfs-overlay/usr/lib/systemd/system/etc-NetworkManager-system\x2dconnections.mount`），
  **NTFS 无法表示**，在 ext4 才完整

产物自动拷回 `output/images/`（Windows 侧）。

### 方式 C：Docker Desktop

```bash
bash scripts/build.sh
```

`scripts/build.sh` 已做 Windows 适配：容器以 root 运行（Windows 无 POSIX
uid 可传），路径用 `cygpath` 转换。

### 三种方式的环境差异对照

| 项 | Actions | WSL2 原生 | Docker Desktop |
|:-|:-|:-|
| glibc | 2.41（debian:trixie） | 2.35（Ubuntu 22.04）—— **需 autoconf 2.72** | 2.41 |
| `/cache` | 容器挂载 | 手动创建 | 容器挂载 |
| PATH | 干净 | **需清理**（WSL 注入 Windows 路径） | 干净 |
| 内核源码 | stable 树 | stable 树 | stable 树 |
| 产物 | Actions artifact | `output/images/` | `.output/` |

---

## 6. 同步机制

```
upstream.pin  ──►  sync-upstream.yml  ──►  PR (改 pin)  ──►  build.yml  ──►  新镜像
```

1. 每日 04:23 UTC 比对上游 `dev` 与 `upstream.pin`
2. 有变化 → 校验板级补丁仍可应用 → 开 PR 更新 pin
3. 合并 PR → 触发 Build → 产出新镜像

### 告警

失败时**绝不静默**：

| 场景 | 行为 |
|:-|:-|
| 同步失败 | 工作流失败（仓库状态变红）+ 开/更新 `sync-failure` Issue（含 SHAs、运行链接、恢复步骤）+ ntfy/Telegram 推送 |
| 构建失败 | 同上，标签为 `build-failure`，并上传 `build.log` 作为 artifact |

推送通知需配置 secret：

| Secret | 用途 |
|:-|:-|
| `NTFY_TOPIC` | ntfy.sh 主题名 |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token |
| `TELEGRAM_CHAT_ID` | Telegram chat id |

### 回滚

```bash
# 回滚 pin
git log --oneline -- upstream.pin
git checkout <commit> -- upstream.pin && git commit -am "Rollback" && git push

# 设备端回滚（A/B 自动，或手动）
rauc install /mnt/data/haos_taishan-<旧版本>.raucb
```

---

## 7. 验证方法

### 自动化

```bash
# 板级配置 + 补丁适用性（含在线拉取真实上游源码校验）
bash scripts/verify-image.sh --config-only

# GitHub 兼容性检查（workflow 文件）
python3 scripts/check-workflow-chars.py

# 镜像结构与分区 PARTUUID 校验
bash scripts/verify-image.sh output/images/haos_taishan-*.img
```

`verify-image.sh` 会联网拉取 stable 内核与 U-Boot 的真实源码，校验两个补丁
能否零偏移应用。

### 已验证结论

| 项目 | 结果 |
|:-|:-|
| 内核补丁 → stable v6.18.59 | ✅ 零偏移干净应用 |
| U-Boot 补丁 → v2026.04 | ✅ 零偏移干净应用 |
| `make taishan_defconfig` | ✅ 成功 |
| `scripts/check-workflow-chars.py` | ✅ 通过（每项均做过注入验证） |
| `verify-image.sh --config-only` | ✅ 9/9 通过 |

### 人工验证（10 级清单）

见 [docs/testing.md](docs/testing.md)：静态检查 → 补丁应用 → 构建 → 镜像结构
→ 启动到 U-Boot → 启动到 HA → 外设 → 存储与升级 → 容量变体 → 1GB 内存表现。

---

## 8. 分区与容量策略

上游 hybrid GPT（GPT + MBR 混合头，Rockchip SPL 兼容）。

| # | 分区 | 大小 | 内容 |
|:-|:-|:-|:-|
| – | `spl` | 16MB | DDR init blob + SPL + U-Boot proper |
| 1 | `hassos-boot` | 16MB | FAT：`boot.scr`、DTB、`cmdline.txt` |
| 2 | `hassos-kernel0` | 24MB | 内核 A |
| 3 | `hassos-system0` | 256MB | EROFS 根文件系统 A |
| 4 | `hassos-kernel1` | 24MB | 内核 B |
| 5 | `hassos-system1` | 256MB | EROFS 根文件系统 B |
| 6 | `hassos-bootstate` | 8MB | U-Boot 环境（A/B 状态、machine-id） |
| 7 | `hassos-overlay` | 96MB | 可写 `/etc` overlay |
| 8 | `hassos-data` | **剩余全部** | Docker 数据、Supervisor 状态、add-on、swapfile |

### eMMC 容量差异的处理

`hassos-data` 是最后一个分区且**没有 size 上限**，`data.ext4` 建于 1280MB
后用 `resize2fs -M` 收缩到最小，首启再扩展。

| eMMC | `hassos-data` 可用 | 说明 |
|:-|:-|:-|
| 8GB | ~7.3GB | 紧张但可用 |
| 16GB | ~15.3GB | 当前配置 |
| 64GB | ~63.3GB | 宽裕 |
| 128GB | ~127.3GB | 宽裕 |

**同一镜像通吃所有容量**。换大容量：写同一个镜像，再把旧 `hassos-data`
分区拷过去即可保留 Home Assistant 配置。

---

## 9. 1GB 内存约束

| 消费者 | 典型占用 |
|:-|:-|
| 内核 + systemd + 基础服务 | ~150MB |
| Supervisor | ~120MB |
| Home Assistant Core | ~350–500MB（随集成/实体数增长） |
| zram swap | 256MB（压缩，实际占用远小） |
| swapfile | 1GiB（磁盘） |

**要点**：Core + Supervisor 需约 500–650MB，1GB 板余量很小。优化方向：

1. Docker 日志上限（`/etc/docker/daemon.json`，`max-size: 10m` / `max-file: 3`）
2. 减少 add-on
3. Recorder `purge_keep_days: 2`
4. 关注 `MemAvailable`（低于 ~150MB 会明显变慢）

详见 [docs/low-memory.md](docs/low-memory.md)。

---

## 10. 排障记录

### 10.1 GitHub Actions：workflow 静默不触发

**症状**：工作流不跑；API 中 `name` 退化为文件路径；运行 0 job 直接 failure。

**三个独立根因**（普通 YAML 解析器都能接受，故极难发现）：

| # | 构造 | 例子 | 处理 |
|:-|:-|:-|:-|
| 1 | 非 ASCII 字符 | em dash（U+2014） | 改 ASCII |
| 2 | name 值里的冒号+空格 | `- name: Restore cache: object files` | 去掉冒号 |
| 3 | `if:` 里直接用 secrets | `if: ${{ secrets.X != '' }}` | 先经 job `env` 暴露，判 `env.X != ''` |

**额外陷阱**：workflow **必须用 `git push` 提交**。经 REST API 写入的文件
不会在 push 事件时重新索引，`name` 永远保持路径 —— 排查时会被误导成
"文件内容有问题"。

**防护**：`scripts/check-workflow-chars.py` 五项全查，作为 Build 第一步。

### 10.2 构建日志被冲断

Buildroot 全量编译输出几万行，**冲断 runner 的日志流**：日志在 39 分钟处
中断，job 又静默跑了 3.7 小时，失败原因完全丢失。

**处理**：编译输出重定向到 `/mnt/output/build.log`，只回显末尾 100 行；
失败时把该文件作为 artifact 上传。缓存保存加 `if: always()`，失败也保留。

### 10.3 Windows 克隆不带执行位

`./scripts/sync-upstream.sh: Permission denied`（exit 126）。git 在 Windows
上不记录可执行位。

**处理**：改用 `bash scripts/xxx.sh` 调用，并把模式记为 `100755`
（`git update-index --chmod=+x`）。

### 10.4 github-script 是 JavaScript

issue body 里的 Markdown 代码块围栏 ` ```bash ` 提前闭合了 JS 模板字符串
→ `SyntaxError: Unexpected identifier 'bash'`；修好后又暴露
`${GITHUB_WORKSPACE}` 被当 JS 变量求值 → `ReferenceError`。

**处理**：围栏写成 `\`\`\``，路径用相对路径。

### 10.5 原生构建的三个环境差异

| 问题 | 原因 | 处理 |
|:-|:-|:-|
| `mkdir: cannot create directory '/cache'` | defconfig 硬编码 `BR2_DL_DIR="/cache/dl"`、`BR2_CCACHE_DIR="/cache/cc"`（容器挂载点约定） | 启动前用 root 建 `/cache` 并开权限 |
| `Your PATH contains spaces, TABs...` | WSL 把 Windows PATH 并入 Linux PATH，带空格与反斜杠，Buildroot 拒绝运行 | 构建前过滤 PATH，只留纯 Linux 路径 |
| `PACKAGE_STRING undeclared` | Buildroot 对 util-linux 跑 `autoreconf`（`UTIL_LINUX_AUTORECONF = YES`），用宿主 autoconf 2.71 重新生成了 util-linux 自带的（2.72 生成的）configure | 装 autoconf 2.72 到 `~/.local/bin` 并置于 PATH 优先 |

### 10.6 下载挂死

`www.zlib.net` 对 zlib-1.3.2 返回 **404**（该版本已撤下），而 Buildroot
的 wget helper **没有总超时**（只有 connect-timeout），于是无限等待。

**处理**：
- `BR2_PRIMARY_SITE=https://sources.buildroot.net`（官方镜像排在 URI 列表最前）
- `BR2_WGET="wget --connect-timeout=15 --timeout=60 --tries=2"`（卡住就换源）
- `scripts/wsl-prefetch.sh` 预取已知失效的包

> 注意：`BR2_WGET` 的值含空格，必须用**数组**传给 make
> （`make "${MAKE_ARGS[@]}"`），否则 make 会把后半段当成自己的参数。

### 10.7 WSL2 的 /tmp 是易失的

实例停止即清空。构建目录必须放 `$HOME`（`~/haos-taishan-build`）。

### 10.8 Actions 建 PR 需要仓库开关

```
GitHub Actions is not permitted to create or approve pull requests.
```

需在 **Settings → Actions → General → Workflow permissions → Allow GitHub
Actions to create and approve pull requests** 打开。**无 API，只能 Web UI**。

### 10.9 多层 shell 的引号与变量展开

Windows 侧（Git Bash）→ `wsl.exe` → WSL 内 bash，三层嵌套时 `$var` 与
反引号会被外层提前展开。**对策**：把逻辑写成独立 `.sh` 文件放进 WSL 执行，
`wsl.exe -- bash /mnt/e/.../script.sh`，避免任何嵌套引号。

---

## 11. 待办与人工步骤

### 需要人工操作（无 API 可用）

| # | 事项 | 位置 |
|:-|:-|:-|
| 1 | 允许 Actions 创建 PR | <https://github.com/sunshijiang/haos-taishan/settings/actions> |
| 2 | （可选）配置推送通知 secret | 同上 → Secrets |

### 后续可选

- 真机验证 10 级清单（[docs/testing.md](docs/testing.md)）
- 发布 Release（`build.yml` 的 `workflow_dispatch` → `publish=true`）
- 上游同步后的镜像回归

---

## 附：文档索引

| 文档 | 内容 |
|:-|:-|
| [docs/build-environment.md](docs/build-environment.md) | 构建依赖、磁盘/内存需求、本地与 CI 构建对比 |
| [docs/building-on-windows.md](docs/building-on-windows.md) | Windows + WSL2 构建（无需 Docker） |
| [docs/parameters.md](docs/parameters.md) | `meta`/defconfig/内核/U-Boot 每个可调项 |
| [docs/hardware-notes.md](docs/hardware-notes.md) | 板级适配逐项说明与原因 |
| [docs/sync-and-rollback.md](docs/sync-and-rollback.md) | 同步机制、告警配置、回滚流程 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 各类故障的诊断与修复 |
| [docs/low-memory.md](docs/low-memory.md) | 1GB 内存下的表现与调优 |
| [docs/testing.md](docs/testing.md) | 10 级验证清单 |
