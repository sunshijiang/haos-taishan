# Parameters reference

Every tunable in this repository, what it does, and when you should change
it.

---

## `board/taishan/meta`

The board metadata. Upstream reads this from `post-build.sh` and
`post-image.sh`.

| Key | Value | Meaning |
|:-|:-|:-|
| `BOARD_ID` | `taishan` | Identifies the board. Drives the image filename (`haos_taishan-…`), the `os-release` `VARIANT_ID`, and the RAUC `compatible` string. |
| `BOARD_NAME` | `LCKFB Taishan Pi RK3566` | Human-readable name shown in `os-release` and the supervisor UI. |
| `CHASSIS` | `embedded` | Reported to the supervisor as the chassis type. |
| `BOOTLOADER` | `uboot` | Selects the RAUC bootloader backend. `uboot` uses `fw_env.config` to store the A/B state; `grub` would use `grubenv`. |
| `KERNEL_FILE` | `Image` | The uncompressed ARM64 kernel image. The kernel is built with LZ4 compression, but the loaded file is `Image` + the compressed payload. |
| `PARTITION_TABLE_TYPE` | `hybrid` | GPT with an MBR hybrid header. Required for Rockchip SPL/loader compatibility. |
| `BOOT_SIZE` | `16M` | Size of the FAT boot partition. Holds `boot.scr`, the DTB and `cmdline.txt`. |
| `BOOT_SPL` | `true` | The board needs the Rockchip DDR init blob and SPL. Enables the `spl.img` partition. |
| `BOOT_SPL_SIZE` | `16M` | Size of the SPL/U-Boot area. |
| `BOOT_ENV_SIZE` | `0x8000` | Size of the U-Boot environment area inside `hassos-bootstate`. Must match the U-Boot `CONFIG_ENV_SECT_SIZE` used by the boot script. |
| `SUPERVISOR_MACHINE` | `green` | Selects the Core container image. See [why green](#why-supervisor_machinegreen). |
| `SUPERVISOR_ARCH` | `aarch64` | Container architecture. |

### Why `SUPERVISOR_MACHINE=green`

The Core container is published as
`ghcr.io/home-assistant/{machine}-homeassistant`. The upstream Core build
matrix contains exactly:

```
generic-x86-64, khadas-vim3, odroid-c2, odroid-c4, odroid-m1, odroid-n2,
qemuarm-64, qemux86-64, raspberrypi3-64, raspberrypi4-64, raspberrypi5-64,
yellow, green
```

`green` is the RK3566 entry. Its Core image is a plain aarch64 Python
runtime with no Green-specific hardware dependencies, so it runs unchanged on
the Taishan Pi.

Changing this to `taishan` would make the build fail at the container fetch
step with a `404` from GHCR, unless you also publish a
`taishan-homeassistant` image to your own registry and patch
`buildroot-external/package/hassio/fetch-container-image.sh`.

---

## `configs/taishan_defconfig`

A Buildroot defconfig. The keys that matter for this board:

### Kernel

| Key | Value | Why |
|:-|:-|:-|
| `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` | `6.18.59` | Kernel version. Must match the `kernel/v6.18.y/` directory in upstream `buildroot-external`. Bump this together with the upstream directory name. |
| `BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` | `…/kernel/v6.18.y/kernel-arm64-rockchip.config` | Base Rockchip kernel configuration. |
| `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` | base + `board/taishan/kernel.config` | Fragments are merged on top of the base config. |
| `BR2_LINUX_KERNEL_INTREE_DTS_NAME` | `rockchip/rk3566-lckfb-tspi` | The mainline Taishan Pi device tree. The build produces `rk3566-lckfb-tspi.dtb`. |
| `BR2_LINUX_KERNEL_DTB_OVERLAY_SUPPORT` | `y` | Enables DT overlays. The boot script applies any found in `overlays/` on the boot partition. |

### U-Boot

| Key | Value | Why |
|:-|:-|:-|
| `BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE` | `2026.04` | The first U-Boot release with `lckfb-tspi-rk3566_defconfig`. |
| `BR2_TARGET_UBOOT_BOARD_DEFCONFIG` | `lckfb-tspi-rk3566` | The mainline Taishan Pi board configuration. |
| `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES` | upstream `bootloader/uboot.config` + `board/taishan/uboot.config` | The upstream fragment supplies `CONFIG_CMD_SETEXPR`, `CONFIG_FS_FAT`, `CONFIG_EFI_PARTITION`. The board fragment adds LED and HS200 options. |
| `BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME` | `u-boot-rockchip.bin` | The name the board hook expects when copying the bootloader into the SPL image. |
| `BR2_PACKAGE_HOST_UBOOT_TOOLS_BOOT_SCRIPT_SOURCE` | `…/board/taishan/uboot-boot.ush` | The boot script, compiled to `boot.scr` by `mkimage`. |

### Rockchip blobs

| Key | Value | Why |
|:-|:-|:-|
| `BR2_PACKAGE_ROCKCHIP_BLOBS_VERSION` | `b4558da0860ca48bf1a571dd33ccba580b9abe23` | The rkbin commit the loader binaries are taken from. |
| `BR2_PACKAGE_ROCKCHIP_BLOBS_ATF` | `bin/rk35/rk3568_bl31_v1.43.elf` | ARM Trusted Firmware. RK3566 uses the RK3568 ATF binary. |
| `BR2_PACKAGE_ROCKCHIP_BLOBS_TPL` | `bin/rk35/rk3566_ddr_1056MHz_v1.18.bin` | DDR training blob. See [DDR failures](#ddr-training-failures). |

### Supervisor and OS agent

| Key | Value | Why |
|:-|:-|:-|
| `BR2_PACKAGE_HASSIO_ARCH` | `aarch64` | Container architecture. |
| `BR2_PACKAGE_HASSIO_MACHINE` | `green` | See above. |
| `BR2_PACKAGE_OS_AGENT_BOARD` | `Supervised` | The os-agent board variant. `Green` would enable os-agent's Green LED features, which expect LEDs named `power`, `activity` and `user`; the Taishan Pi has `status-red`, `status-green` and `status-blue`, so those calls would fail. `Supervised` registers no board-specific features and the generic path applies. |

### Root filesystem

| Key | Value | Why |
|:-|:-|:-|
| `BR2_TARGET_ROOTFS_EROFS` | `y` | EROFS root filesystem, read-only. |
| `BR2_TARGET_ROOTFS_EROFS_LZ4HC_LEVEL` | `12` | Compression level. Higher means smaller and slower to decompress. |
| `BR2_TARGET_ROOTFS_EROFS_PCLUSTERSIZE` | `262144` | Cluster size in bytes (256 KiB). |

---

## `board/taishan/kernel.config`

Kernel configuration fragments, merged on top of
`kernel-arm64-rockchip.config`.

| Option | Why |
|:-|:-|
| `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y` | RK3566 boards run at full clock; the `ondemand` governor causes visible latency in Home Assistant. |
| `CONFIG_THERMAL_GOV_BANG_BANG=y` | RK3566 thermal throttling. Matches the Green board. |
| `CONFIG_SENSORS_GPIO_FAN=y` | Allows a GPIO-controlled fan if one is wired. |
| `CONFIG_KEYBOARD_GPIO=y` | GPIO buttons on the 40-pin header. |
| `CONFIG_KEYBOARD_GPIO_POLLED=y` | The RK3566 GPIO block cannot report interrupts on all pins, so polling is required. |
| `CONFIG_MMC_SDHCI_OF_DWCMSHC=y` | The Rockchip eMMC controller. |
| `CONFIG_MMC_SDHCI_SDMA=y` | Required by the AP6212 WiFi module on SDIO. |
| `# CONFIG_RTC_DRV_RK808 is not set` | The Taishan Pi uses the RK809, whose RTC is handled by the `rk8xx` driver. |
| `# CONFIG_DW_WATCHDOG is not set` | The DesignWare watchdog is not wired up on this board. |

The upstream base config already provides `CONFIG_KEYBOARD_ADC=m`, which is
what makes the Recovery button work.

---

## `board/taishan/uboot.config`

U-Boot configuration fragments, merged on top of the mainline
`lckfb-tspi-rk3566_defconfig`.

| Option | Why |
|:-|:-|
| `CONFIG_LED=y`, `CONFIG_LED_GPIO=y`, `CONFIG_CMD_LED=y` | The `led user on` call in the boot script, used during the device-wipe countdown. |
| `CONFIG_MMC_HS200_SUPPORT=y`, `CONFIG_SPL_MMC_HS200_SUPPORT=y` | RK356x eMMC must use HS200; DDR52 corrupts writes. |

---

## `board/taishan/uboot-boot.ush`

The U-Boot boot script. Key parameters:

| Parameter | Value | Meaning |
|:-|:-|:-|
| `BOOT_ENV_SIZE` | `0x8000` | Matches `meta`. The `env import`/`env export` size for the boot-state area. |
| `BOOT_A_LEFT` / `BOOT_B_LEFT` | `3` | Number of boot attempts per slot before falling back. |
| `BOOT_ORDER` | `A B` | Which slot to try first. RAUC rewrites this when marking a slot bad. |
| `ha_version` | `rk3566-lckfb-tspi.dtb` | The device tree file loaded from the boot partition. Must match `BR2_LINUX_KERNEL_INTREE_DTS_NAME`. |
| `bootargs_a` / `bootargs_b` | fixed PARTUUIDs | The root filesystem of each slot. These UUIDs come from upstream `partitions-os-gpt.cfg` and must not be changed without updating the image generator too. |
| `check_btn_pressed` | I²C 0x20, reg 0xf0 | Detects the power button for the device-wipe flow. |

---

## `upstream.pin`

```
<40-char sha> <iso date> <label>
```

The exact upstream commit the build uses. The `Sync upstream` workflow
compares it against the upstream `dev` branch daily and opens a pull request
when they differ.

---

## Build-time environment variables

| Variable | Default | Purpose |
|:-|:-|:-|
| `UPSTREAM_REPO` | `https://github.com/home-assistant/operating-system.git` | Upstream source. |
| `UPSTREAM_REF` | `dev` | Upstream branch used by `check-upstream.sh`. |

---

## Frequently changed values

### Kernel version bump

When upstream moves to a new kernel series:

1. Update `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` in `configs/taishan_defconfig`.
2. Check whether upstream renamed `kernel/v6.18.y/` to `kernel/v6.19.y/`. If
   so, update `BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` and the fragment paths.
3. Re-apply the kernel patch — the device tree line numbers will have moved:

```bash
./scripts/sync-upstream.sh --ref dev --dest /tmp/up
cd /tmp/up/buildroot
git apply --check \
    ~/haos-taishan/board/taishan/patches/linux/0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch
```

4. Rebuild and re-test on hardware.

### DDR training failures

If the board does not start and the serial console shows nothing, the DDR
training blob is the first suspect — the LPDDR4 density on the Taishan Pi
varies between board revisions. Try a lower frequency blob:

```
BR2_PACKAGE_ROCKCHIP_BLOBS_TPL="bin/rk35/rk3566_ddr_920MHz_v1.18.bin"
```

The full list of available blobs:

```bash
curl -s "https://api.github.com/repos/rockchip-linux/rkbin/contents/bin/rk35?ref=<version>" \
  | grep rk3566_ddr
```

Candidates for the Taishan Pi, in order of preference:

| Blob | Use when |
|:-|:-|
| `rk3566_ddr_1056MHz_v1.18.bin` | Default. Works on most 1/2/4/8 GB boards. |
| `rk3566_ddr_920MHz_v1.18.bin` | The 1056 MHz blob fails to train DDR. |
| `rk3566_ddr_780MHz_ultra_v1.10.bin` | Still failing; lower frequency, older revision. |
| `rk3566_ddr_528MHz_ultra_v1.10.bin` | Last resort; slow but boots. |
