# HAOS for LCKFB Taishan Pi (RK3566)

Home Assistant Operating System for the **LCKFB Taishan Pi** (立创·泰山派), a
RK3566 single-board computer. This repository builds an official-compatible
HAOS image for that board and keeps it in sync with
[home-assistant/operating-system](https://github.com/home-assistant/operating-system).

The image boots Home Assistant only. It contains no desktop, no general
purpose package manager and no extra services — the same minimal container
platform that powers the official Home Assistant Green.

---

## 1. Target hardware

| Item | Value |
|:-|:-|
| SoC | Rockchip RK3566, 4× Cortex-A55 @ up to 1.8 GHz, Mali-G52 2EE, NPU 1 TOPS |
| RAM | LPDDR4 / LPDDR4X — 1 GB (current), 2 / 4 / 8 GB variants exist |
| Storage | eMMC — 16 GB (current), 8 / 32 / 64 / 128 GB variants exist; plus a TF card slot |
| PMIC | Rockchip RK809 (I²C0 @ 0x20), 1.0 W onboard speaker + microphone |
| Network | 100/1000 Ethernet (GMAC + PHY), onboard 2.4 GHz Wi-Fi/BT (AP6212) |
| USB | 1× USB 3.0 (Type-A), 2× USB 2.0 (Type-A), 1× USB Type-C (power) |
| Storage expansion | SATA, mini PCIe (via 39-pin high-speed header), TF card (up to 512 GB) |
| Display | micro-HDMI (4K@60), EDP, MIPI DSI |
| Other | 40-pin GPIO header (Raspberry Pi compatible), RGB status LED, Recovery + Reset buttons |

**Purpose:** running Home Assistant and nothing else. The board is used as a
home automation hub, so the image is trimmed to the OS + Supervisor + Docker
stack that HAOS provides.

---

## 2. How this repository relates to upstream

Home Assistant OS is a Buildroot-based distribution whose build system lives
in `home-assistant/operating-system`. That tree is large (500+ files) and
changes frequently — upstream lands new kernel versions roughly every two
weeks.

Forking it would mean merging upstream changes by hand forever. Instead this
repository keeps **only the Taishan Pi specific parts** and pulls upstream at
build time:

```
sunshijiang/haos-taishan
├── board/taishan/          # the entire board customisation
├── configs/taishan_defconfig
├── scripts/                # sync + build + verify
├── upstream.pin            # the exact upstream commit we build against
└── .github/workflows/      # build, upstream sync, failure alerting
```

At build time `scripts/sync-upstream.sh` checks out upstream at the pinned
commit and copies the board overlay on top. An upstream sync is therefore a
plain "git fetch + checkout" plus a patch refresh — never a merge conflict.

### What is actually customised

| Area | Approach | Why |
|:-|:-|:-|
| Device tree | **Reuses mainline** `rockchip/rk3566-lckfb-tspi` | The Taishan Pi DTS is in the mainline kernel since 6.16 |
| U-Boot | **Reuses mainline** `lckfb-tspi-rk3566_defconfig` | Present in U-Boot since v2026.04 |
| eMMC | One kernel patch (HS200) | RK356x corrupts writes in DDR52 mode |
| U-Boot | One patch (HAOS boot options) | Mainline defconfig lacks `CMD_PART`/`CMD_FAT`/`CMD_FILEENV` |
| Boot script | Adapted copy of the Green board script | Same A/B + RAUC flow, different PMIC and no SPI NOR |
| Supervisor | `machine=green` | See below |

### Why `SUPERVISOR_MACHINE=green`

`BR2_PACKAGE_HASSIO_MACHINE` selects the container image
`ghcr.io/home-assistant/{machine}-homeassistant`. The upstream Core build
matrix lists exactly these machines:

```
generic-x86-64, khadas-vim3, odroid-c2, odroid-c4, odroid-m1, odroid-n2,
qemuarm-64, qemux86-64, raspberrypi3-64, raspberrypi4-64, raspberrypi5-64,
yellow, green
```

There is no `taishan` machine, and creating one would mean maintaining a
fork of `home-assistant/core` and publishing it to GHCR. The `green` machine
is the right reuse: it is the **same RK3566 SoC, same aarch64 architecture**,
and its Core image is a generic Python runtime with no Green-specific
hardware assumptions. `BR2_PACKAGE_OS_AGENT_BOARD` is set to `Supervised`
because the Green-specific os-agent board features drive LEDs named
`power`/`activity`/`user`, which the Taishan Pi does not have (it has
`status-red`/`status-green`/`status-blue`).

The board keeps its own identity through `BOARD_ID=taishan`, which drives the
image filename, the `os-release` variant and the RAUC `compatible` string
(`haos-taishan`), so it never collides with the official Green image.

---

## 3. One setting to turn on

The sync workflow opens a pull request with the built in `GITHUB_TOKEN`.
GitHub only allows that when this is on:

**Settings -> Actions -> General -> Workflow permissions -> Allow GitHub
Actions to create and approve pull requests**

<https://github.com/sunshijiang/haos-taishan/settings/actions>

There is no API for it, so it has to be set in the web interface. Without it
the sync job fails with *"GitHub Actions is not permitted to create or
approve pull requests"*, and the alert workflow opens an issue that says so.

The alert workflow also sends a push notification when a secret is set, see
[the rollback guide](docs/sync-and-rollback.md#alerting).

---

## 4. Building

### Prerequisites

* Docker (the build runs inside the upstream `debian:trixie` builder image)
* `git`, `bash`, `python3`, `xz`
* ~60 GB free disk, ~16 GB RAM (a GitHub Actions runner is enough)

### Quick start

```bash
git clone https://github.com/sunshijiang/haos-taishan.git
cd haos-taishan

./scripts/build.sh
```

The build takes roughly 40-90 minutes on a GitHub-hosted runner. The
compiler cache is stored between runs, so only the first build pays the full
price.

The Build workflow also runs `scripts/check-workflow-chars.py` before
anything else. GitHub rejects a workflow file that contains an em dash, a
colon in a name value, or the secrets context in an `if` condition, and it
does so silently: the workflow keeps an entry but never runs. The check
turns that into an immediate, readable failure.

### What the build does

1. `scripts/sync-upstream.sh` clones upstream at the pinned commit,
   initialises the `buildroot` submodule, and overlays `board/taishan/`
   and `configs/taishan_defconfig` onto it.
2. The upstream `Dockerfile` is built into a builder image
   (`debian:trixie` + buildroot toolchain + `skopeo`).
3. `make taishan_defconfig` generates the Buildroot configuration.
4. `make` cross-compiles the kernel, U-Boot, and the root filesystem, then
   `post-image.sh` runs `genimage` to lay out the partitions and builds the
   RAUC bundle.
5. `make linux-check-dotconfig` verifies the kernel configuration fragments
   are consistent.

### Outputs

| File | Purpose |
|:-|:-|
| `haos_taishan-<version>.img.xz` | Raw disk image, xz-compressed. Write to a TF card or eMMC. |
| `haos_taishan-<version>.raucb` | RAUC bundle. Use for OTA and USB updates. |

Artifacts are attached to every successful CI run and can be published as a
GitHub release from the **Build** workflow (`workflow_dispatch` → *publish*).

---

## 5. Flashing and updating

### First install

**To a TF card** (the board boots from the TF card first):

```bash
xz -dc haos_taishan-*.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

**To the eMMC** — either write the same image to the eMMC device, or boot
from the TF card and copy the image over:

```bash
# from a booted system, with the eMMC visible as /dev/mmcblk0
sudo dd if=haos_taishan.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

> **Boot order.** U-Boot's `rk356x-u-boot.dtsi` sets
> `u-boot,spl-boot-order = "same-as-spl", &sdmmc0, &sdhci`, i.e. the TF card
> is probed before the eMMC. If you keep a system on the TF card it will win
> over the eMMC. Remove the card, or reflash the eMMC, to boot from eMMC.

### Upgrading

| Method | How |
|:-|:-|
| OTA (in Home Assistant) | *Settings → System → Updates*. Uses RAUC and the A/B slot mechanism. |
| OTA (command line) | `ha os update` then `ha os restart`. |
| Manual / USB | Copy the `.raucb` to the board and run `rauc install /mnt/data/xxx.raucb`. |

Updates are A/B: the new system and kernel are written to the inactive slot,
and the bootloader switches over only if the new system boots successfully.
If it does not, the board falls back to the previous slot after three
attempts.

---

## 6. Partition layout

The image uses the same layout as the official HAOS Green board
(`PARTITION_TABLE_TYPE=hybrid`, i.e. GPT with an MBR hybrid header):

| # | Partition | Size | Notes |
|:-|:-|:-|:-|
| – | `spl` | 16 MB | DDR init + U-Boot SPL, not in the partition table |
| – | `uboot` | 32 kB offset | U-Boot proper, inside the SPL image |
| 1 | `hassos-boot` | 16 MB | FAT, holds `boot.scr`, the DTB and `cmdline.txt` |
| 2 | `hassos-kernel0` | 24 MB | Kernel for slot A |
| 3 | `hassos-system0` | 256 MB | EROFS rootfs for slot A |
| 4 | `hassos-kernel1` | 24 MB | Kernel for slot B |
| 5 | `hassos-system1` | 256 MB | EROFS rootfs for slot B |
| 6 | `hassos-bootstate` | 8 MB | U-Boot environment (A/B state) |
| 7 | `hassos-overlay` | 96 MB | Writable `/etc` overlay |
| 8 | `hassos-data` | rest of the device | Docker data, Supervisor state, add-ons |

### eMMC capacity differences

**One image works on 16 GB, 64 GB and 128 GB boards.** The fixed partitions
above total about 700 MB. `hassos-data` is the last partition and has no
size limit, so it absorbs whatever the device offers. The `data.ext4` image
inside it is built at a fixed 1280 MB and then shrunk with `resize2fs -M` to
its minimum size; on first boot the filesystem grows into the free space.

Practical consequence:

| eMMC | Free for `hassos-data` | Notes |
|:-|:-|:-|
| 8 GB | ~7.3 GB | Tight but workable |
| 16 GB | ~15.3 GB | Current configuration |
| 64 GB | ~63.3 GB | Comfortable |
| 128 GB | ~127.3 GB | Comfortable |

If you move from a smaller to a larger eMMC, write the same image to the new
device — the data partition simply becomes larger. Your Home Assistant
configuration lives in `hassos-data`; **copy that partition across** if you
want to keep your existing setup.

---

## 7. Keeping in sync with upstream

The **Sync upstream** workflow runs daily at 04:23 UTC:

1. It compares the upstream `dev` branch against the commit in
   `upstream.pin`.
2. If upstream moved, it opens (or updates) a pull request that bumps the
   pin — after verifying that the Taishan Pi patches still apply.
3. Merging the PR re-triggers the **Build** workflow, producing a fresh
   image.

```
upstream.pin  ──►  sync-upstream.yml  ──►  PR (pin bump)  ──►  build.yml  ──►  new image
```

### When the sync fails

Failure is never silent. The workflow:

* fails the job, so the repository status turns red;
* opens (or updates) a GitHub issue labelled `sync-failure`, containing the
  pinned SHA, the new upstream SHA, a link to the run, and step-by-step
  recovery instructions;
* sends an out-of-band notification when a secret is configured:
  * `NTFY_TOPIC` → push to [ntfy.sh](https://ntfy.sh);
  * `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` → Telegram message.

The **Alert on build failure** workflow does the same for a failed build,
using the `build-failure` label.

To enable push notifications, add the secrets under
*Settings → Secrets and variables → Actions*:

| Secret | Purpose |
|:-|:-|
| `NTFY_TOPIC` | Topic name to publish to on ntfy.sh |
| `TELEGRAM_BOT_TOKEN` | Bot token for Telegram |
| `TELEGRAM_CHAT_ID` | Chat ID to message |

The notification steps read the secrets from the job environment, because a
secret cannot be used directly in an `if` condition:

```yaml
    env:
      NTFY_TOPIC: ${{ secrets.NTFY_TOPIC }}

    steps:
      - name: Send an out-of-band notification
        if: env.NTFY_TOPIC != ''
```

### Rollback

```bash
# 1. Find the last good upstream commit
git log --oneline upstream.pin

# 2. Pin it and rebuild
echo "<sha> $(date -u +%F) rollback" > upstream.pin
git commit -am "Rollback upstream pin to <sha>"
git push
```

The **Build** workflow then produces an image from the older upstream tree.
On the device itself, an A/B rollback is automatic: if the new system fails
to boot three times, U-Boot returns to the other slot.

To roll back on the device without rebuilding, install an older `.raucb`:

```bash
rauc install /mnt/data/haos_taishan-<older-version>.raucb
```

---

## 8. Documentation

| Document | Contents |
|:-|:-|
| [docs/PROJECT.md](docs/PROJECT.md) | **Complete project reference: hardware, upstream facts, build, sync, troubleshooting** |
| [docs/build-environment.md](docs/build-environment.md) | Build dependencies, disk/RAM requirements, local vs CI builds |
| [docs/building-on-windows.md](docs/building-on-windows.md) | Building on Windows with WSL2, no Docker needed |
| [docs/parameters.md](docs/parameters.md) | Every tunable in `meta`, `defconfig`, kernel and U-Boot config |
| [docs/hardware-notes.md](docs/hardware-notes.md) | Board-specific adaptations and why each one is needed |
| [docs/sync-and-rollback.md](docs/sync-and-rollback.md) | Upstream sync mechanics, alerting, rollback procedures |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failures and how to diagnose them |
| [docs/low-memory.md](docs/low-memory.md) | Running on 1 GB RAM: what to expect and how to tune it |
| [docs/testing.md](docs/testing.md) | The verification checklist, automated and manual |

---

## 9. Licence and attribution

The board customisation in this repository is distributed under the
Apache-2.0 licence, matching upstream Home Assistant OS.

Upstream components keep their own licences: Home Assistant OS
(Apache-2.0), Buildroot (GPL-2.0), Linux (GPL-2.0), U-Boot (GPL-2.0),
Docker (Apache-2.0), RAUC (LGPL-2.1).

The Taishan Pi device tree is the work of LCKFB and is included in the mainline
Linux kernel under the GPL-2.0 licence.
