# Hardware notes

Everything this repository changes relative to the upstream Home Assistant OS
build, and the reason for each change. Every claim here is derived from the
upstream tree at the pinned commit or from the mainline kernel and U-Boot
sources.

---

## 1. SoC support: RK3566

RK3566 support in Home Assistant OS comes from the **Home Assistant Green**
board, which uses the same SoC. That board's directory
(`buildroot-external/board/nabucasa/green/`) is the template this work
follows.

What upstream already provides that a RK3566 board needs:

| Component | Upstream location | Version |
|:-|:-|:-|
| Kernel base config | `buildroot-external/kernel/v6.18.y/kernel-arm64-rockchip.config` | 6.18.59 |
| Kernel fragments | `haos.config`, `docker.config`, `device-support.config`, `device-support-wireless.config` | — |
| U-Boot | `BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="2026.04"` | 2026.04 |
| Rockchip loader blobs | `BR2_PACKAGE_ROCKCHIP_BLOBS_*` | rkbin `b4558da0860ca48bf1a571dd33ccba580b9abe23` |
| Partition layout | `buildroot-external/genimage/partitions-os-gpt.cfg` | — |
| RAUC configuration | `buildroot-external/ota/system.conf.gtpl` | — |
| Boot-state handling | `buildroot-external/board/nabucasa/green/uboot-boot.ush` | — |

Nothing in the kernel or bootloader needed to be written from scratch. The
Taishan Pi's own device tree and U-Boot configuration are already in mainline
(see below), which is why the patch surface is only two small patches.

---

## 2. Device tree: `rockchip/rk3566-lckfb-tspi`

The mainline kernel carries the Taishan Pi device tree:

```
arch/arm64/boot/dts/rockchip/rk3566-lckfb-tspi.dts
```

with `model = "LCKFB Taishan Pi RK3566"` and
`compatible = "lckfb,tspi-rk3566", "rockchip,rk3566"`.

The build simply references it:

```
BR2_LINUX_KERNEL_INTREE_DTS_NAME="rockchip/rk3566-lckfb-tspi"
```

### What that device tree already covers

| Subsystem | Device tree node | Notes |
|:-|:-|:-|
| eMMC | `&sdhci` | 8-bit, 200 MHz, non-removable, with `emmc_datastrobe` |
| TF card | `&sdmmc0` | 4-bit, 150 MHz, UHS-I |
| WiFi/BT | `&sdmmc1` + `brcmf` | AP6212 (BCM4329 fmac, BCM43438 BT) |
| Ethernet | `&gmac0`/`&gmac1` | 100/1000 with Rockchip PHY |
| USB | `&usb_host0_*`, `&usb_host1_*` | USB 3.0 + two USB 2.0 ports |
| PMIC | `rk809: pmic@20` on I²C0 | All regulators, audio codec, RTC |
| Audio | `simple-audio-card` with `&rk809` | Speaker, microphone, headphone |
| Display | `&hdmi`, `&vop`, `&vp0` | HDMI 2.0 |
| RGB LED | `rgb_led_r/g/b` on GPIO1 PB2/PB1/PB0 | Active low, plus a `leds-group-multicolor` group |
| Recovery button | `adc_keys` → SARADC channel 0 | `linux,code = <KEY_RESTART>` |
| USB power | `vcc5v0_host` with a GPIO enable on GPIO4 PC4 | — |

### The one device tree change we make

**`mmc-hs200-1_8v` on `&sdhci`.**

The upstream Taishan Pi DTS does not enable HS200. On RK356x, the MMC DDR52
mode produces corrupt writes with some eMMC devices; only HS200 is reliable.
Upstream Home Assistant made exactly this change for the Green board, whose
commit message is *"green: emmc use HS200 mode"*.

Without it, the `hassos-data` partition can be silently corrupted while Home
Assistant writes its state — a failure that is especially unpleasant on the
1 GB boards because there is little free space to recover into.

Patch: `board/taishan/patches/linux/0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch`

---

## 3. U-Boot: `lckfb-tspi-rk3566_defconfig`

U-Boot v2026.04 carries the Taishan Pi board configuration:

```
configs/lckfb-tspi-rk3566_defconfig
```

It sets `CONFIG_DEFAULT_DEVICE_TREE="rockchip/rk3566-lckfb-tspi"` and
`CONFIG_DEFAULT_FDT_FILE="rockchip/rk3566-lckfb-tspi.dtb"`, and U-Boot
imports the same device tree from `dts/upstream/src/arm64/rockchip/`.

### The one U-Boot change we make

The mainline board defconfig is a plain board config. The HAOS boot script
needs three more commands:

| Option | Used for |
|:-|:-|
| `CONFIG_CMD_PART` | `part start` and `part number` to locate `hassos-boot`, `hassos-kernel0`, `hassos-kernel1` by GPT partition number |
| `CONFIG_CMD_FAT` | `fatload` to read `haos-config.txt`, `cmdline.txt` and the DTB from the FAT boot partition |
| `CONFIG_CMD_FILEENV` | `fileenv` to source `cmdline.txt` into `${cmdline}` |

`CONFIG_PARTITIONS` itself comes from `CONFIG_EFI_PARTITION`, which the shared
upstream fragment `buildroot-external/bootloader/uboot.config` already
enables.

The same patch enables `CONFIG_MMC_HS200_SUPPORT` and
`CONFIG_SPL_MMC_HS200_SUPPORT`, mirroring the kernel side.

Patch: `board/taishan/patches/uboot/0001-configs-lckfb-tspi-rk3566-enable-HAOS-required-options.patch`

---

## 4. Boot script differences from the Green board

`board/taishan/uboot-boot.ush` is derived from
`buildroot-external/board/nabucasa/green/uboot-boot.ush`.

| Aspect | Green | Taishan Pi |
|:-|:-|:-|
| SPI NOR flash | Yes, probed first in the SPL boot order | **No** |
| PMIC | RK808 | **RK809** (same I²C0 @ 0x20, same 0xf0 register layout) |
| Device wipe trigger | Hold the power button (RK808 PWRON bit) | Same probe, unchanged |
| Recovery button | — | **ADC key** on SARADC channel 0 — handled by the kernel, not readable from U-Boot |
| Boot media | eMMC (`&sdhci`) | **TF card first** (`&sdmmc0`), then eMMC |
| Device tree | `rk3566-ha-green.dtb` | `rk3566-lckfb-tspi.dtb` |

### Why the wipe probe still works

The boot script reads the power-button state over I²C:

```
i2c dev 0
i2c read 0x20 0xf0.1 1 ${loadaddr}
setexpr PWRON_STS *${loadaddr} & 0x80
```

Register `0xf0` is `RK817_SYS_STS` in the Linux `rk8xx` driver. The RK809
shares the RK817 register map (the kernel driver treats `rockchip,rk809` and
`rockchip,rk817` identically), and the RK809 sits at I²C0 address `0x20` —
the same address as the RK808 on the Green board. The probe therefore works
unchanged.

### The Recovery button

The Taishan Pi's Recovery button is an ADC key
(`adc-keys` → `button-recovery`, `linux,code = <KEY_RESTART>`). The kernel
has `CONFIG_KEYBOARD_ADC=m`, so the button works once Linux is running. It
**cannot** be used to trigger the device wipe from U-Boot, because the
mainline `lckfb-tspi-rk3566_defconfig` does not enable the Rockchip SARADC
driver for U-Boot. Use the power button for the wipe instead.

### Boot order

U-Boot's `rk356x-u-boot.dtsi` sets:

```
u-boot,spl-boot-order = "same-as-spl", &sdmmc0, &sdhci;
```

The TF card is probed **before** the eMMC. The boot script itself does not
hard-code a device — it uses `${devtype}`/`${devnum}` as set by the SPL/U-Boot
stage — so a single image boots from either medium.

If a TF card with an older system stays in the slot, it will keep winning
over the eMMC. Remove the card to boot from eMMC.

---

## 5. Storage and partition layout

The layout is the upstream hybrid (GPT + MBR header) layout used by the
Green board.

| Partition | Size | Filesystem | Contents |
|:-|:-|:-|:-|
| `spl` | 16 MB | raw | DDR init blob (`ddr_*.bin`) + SPL + U-Boot proper |
| `hassos-boot` | 16 MB | FAT32 | `boot.scr`, `rk3566-lckfb-tspi.dtb`, `cmdline.txt`, `haos-config.txt` |
| `hassos-kernel0` | 24 MB | raw | Kernel, slot A |
| `hassos-system0` | 256 MB | EROFS | Root filesystem, slot A |
| `hassos-kernel1` | 24 MB | raw | Kernel, slot B |
| `hassos-system1` | 256 MB | EROFS | Root filesystem, slot B |
| `hassos-bootstate` | 8 MB | raw | U-Boot environment (A/B state, machine ID) |
| `hassos-overlay` | 96 MB | ext4 | Writable `/etc` overlay |
| `hassos-data` | remainder | ext4 | Docker data root, Supervisor state, add-ons, swapfile |

Fixed partitions total roughly 700 MB.

### Capacity differences

`hassos-data` is the last partition and carries **no size limit** in
`partitions-os-gpt.cfg`, so genimage gives it everything that is left. The
`data.ext4` image placed inside it is created at a fixed 1280 MB and then
shrunk with `e2fsck` + `resize2fs -M` to its actual minimum size; the
filesystem grows into the free space on first boot.

Consequences:

* **The same image works on 8 GB, 16 GB, 64 GB and 128 GB eMMC.** No
  per-size image is needed.
* Moving to a larger eMMC: write the same image, then copy the old
  `hassos-data` partition across if you want to keep your configuration.
* Moving to a smaller eMMC: not supported without re-imaging. The minimum is
  8 GB, and even that leaves only ~7.3 GB for `hassos-data`.

### Swap file

`hassos-data` also holds the swapfile created by `haos-swapfile`. It defaults
to 33 % of RAM, clamped to between 1 GiB and 4 GiB — so **1 GB minimum even
on a 1 GB board**. See [low-memory.md](low-memory.md).

---

## 6. Board-specific summary

| Item | Status |
|:-|:-|
| RK3566 support | Inherited from the upstream Green board; nothing to port |
| Device tree | Mainline `rk3566-lckfb-tspi`, one HS200 patch |
| U-Boot | Mainline `lckfb-tspi-rk3566_defconfig`, one options patch |
| Kernel version | 6.18.59, same as all other mainline boards |
| eMMC | HS200, 200 MHz, 8-bit |
| TF card | Bootable, probed before the eMMC |
| Storage sizes | One image for every eMMC size |
| Boot method | U-Boot SPL + A/B slots + RAUC |
| Wipe trigger | Power button over I²C (RK809, same as Green) |
| Recovery button | ADC key, kernel-side only |
| LEDs | RGB on GPIO1 PB2/PB1/PB0, active low, `leds-group-multicolor` |
| WiFi/BT | AP6212, requires `CONFIG_MMC_SDHCI_SDMA` |
| Audio | RK809 codec, `simple-audio-card` |
| Ethernet | Rockchip GMAC with integrated PHY |
