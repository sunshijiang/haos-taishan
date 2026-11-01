# Testing checklist

A repeatable checklist for validating a build, from static checks through to
a running Home Assistant on the device.

---

## Level 1 — Static checks (no hardware needed)

Automated:

```bash
./scripts/verify-image.sh --config-only
```

Expected: `Passed: 9, Failed: 0`.

The checks confirm that the board directory, the defconfig and both patches
exist; that the defconfig points at the mainline Taishan Pi device tree and
U-Boot defconfig; that the supervisor machine is one that actually exists on
GHCR; and that HS200 is enabled.

Manual review:

- [ ] `configs/taishan_defconfig` pins a kernel version that matches the
      `kernel/v6.18.y/` directory upstream
- [ ] `BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE` is a U-Boot release that
      contains `configs/lckfb-tspi-rk3566_defconfig` (2026.04 or newer)
- [ ] `BR2_PACKAGE_ROCKCHIP_BLOBS_TPL` points at a file that exists in the
      pinned rkbin commit
- [ ] No absolute paths or machine-specific values in the board files

## Level 2 — Patch application

```bash
./scripts/sync-upstream.sh --ref dev --dest /tmp/verify
cd /tmp/verify/buildroot
git apply --check /path/to/haos-taishan/board/taishan/patches/linux/*.patch
```

- [ ] The kernel patch applies cleanly against the current upstream kernel
- [ ] The U-Boot patch applies cleanly against U-Boot v2026.04
- [ ] `board/taishan/` was copied into `buildroot-external/board/taishan/`
- [ ] `configs/taishan_defconfig` was copied into `buildroot-external/configs/`
- [ ] `.github/workflows/matrix.json` now contains the `taishan` entry

## Level 3 — Build

- [ ] `make taishan_defconfig` completes
- [ ] `make` completes without errors
- [ ] `make linux-check-dotconfig` passes
- [ ] `output/images/haos_taishan-<version>.img.xz` exists
- [ ] `output/images/haos_taishan-<version>.raucb` exists
- [ ] The kernel image contains `rk3566-lckfb-tspi.dtb`
- [ ] `boot.scr` was generated from `board/taishan/uboot-boot.ush`

## Level 4 — Image structure

```bash
./scripts/verify-image.sh /tmp/verify/output/images/haos_taishan-*.img
```

- [ ] `hassos-boot` partition present (16 MB, FAT)
- [ ] `hassos-kernel0` and `hassos-kernel1` present (24 MB each)
- [ ] `hassos-system0` and `hassos-system1` present (256 MB each)
- [ ] `hassos-bootstate` present (8 MB)
- [ ] `hassos-overlay` present (96 MB)
- [ ] `hassos-data` present and last
- [ ] PARTUUID `8d3d53e3-6d49-4c38-8349-aff6859e82fd` present (slot A root)
- [ ] PARTUUID `a3ec664e-32ce-4665-95ea-7ae90ce9aa20` present (slot B root)

The last two matter most: the boot script hard-codes them, and a mismatch
means the board boots to U-Boot and then fails to mount the root filesystem.

## Level 5 — Boot to U-Boot

Write the image to a TF card:

```bash
xz -dc haos_taishan-*.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Attach a serial console at **1500000 baud, 8N1**.

- [ ] The board powers on and the RGB LED lights
- [ ] U-Boot prints its banner (`HAOS> ` prompt is set in the upstream
      fragment)
- [ ] The DDR training succeeds (no "DDR init failed")
- [ ] U-Boot finds `hassos-boot` and loads `boot.scr`
- [ ] U-Boot prints `Loading standard device tree rk3566-lckfb-tspi.dtb`
- [ ] U-Boot prints `Trying to boot slot A, 3 attempts remaining`
- [ ] The kernel starts (`Starting kernel` followed by Linux boot messages)

## Level 6 — Boot to Home Assistant

- [ ] The kernel reaches the systemd target without `Failed to mount root fs`
- [ ] `systemd-analyze` shows no critical unit failures
- [ ] NetworkManager brings up the Ethernet interface
- [ ] The Supervisor container starts
- [ ] Home Assistant Core starts and the UI is reachable at
      `http://<board-ip>:8123`
- [ ] The Supervisor reports the correct OS version and machine

```bash
ha os info
ha supervisor info
ha core info
```

## Level 7 — Hardware peripherals

- [ ] Ethernet: `ip link` shows the interface up; a sustained transfer has no
      errors (`ip -s link`)
- [ ] WiFi: the AP6212 is detected (`dmesg | grep -i brcmf`) and can connect
      to an access point
- [ ] Bluetooth: `bluetoothctl list` finds a device
- [ ] USB 3.0: a USB 3.0 stick mounts at the expected speed
- [ ] USB 2.0: a USB 2.0 device is detected
- [ ] HDMI: a monitor reports a signal; the resolution is as expected
- [ ] Audio: a speaker produces sound; the microphone records
- [ ] RGB LED: visible in `ls /sys/class/leds/`
- [ ] Recovery button: pressing it triggers a reboot (it is an ADC key with
      `linux,code = <KEY_RESTART>`)
- [ ] Reset button: reboots the board
- [ ] The 40-pin header: GPIO read and write work

## Level 8 — Storage and updates

- [ ] The `hassos-data` partition size matches the eMMC capacity
- [ ] `df -h` shows the data partition sized to the device
- [ ] A reboot preserves the Home Assistant configuration
- [ ] The zram devices are present: `zramctl`
- [ ] The swapfile exists: `swapon --show`
- [ ] An OTA update succeeds: *Settings → System → Updates*
- [ ] After the update, the system runs the new version
- [ ] A failed update rolls back to the previous slot automatically
- [ ] A manual RAUC install works: `rauc install /mnt/data/<bundle>.raucb`

## Level 9 — Capacity variants

Repeat Level 5 and 6 on the other capacity configurations:

- [ ] 8 GB eMMC: boots, `hassos-data` gets the remaining space
- [ ] 64 GB eMMC: boots, `hassos-data` gets the remaining space
- [ ] 128 GB eMMC: boots, `hassos-data` gets the remaining space
- [ ] 2 GB / 4 GB / 8 GB RAM: boots and reports the correct `MemTotal`

The image is identical across all of these; only the `hassos-data` partition
size and the swapfile size differ.

## Level 10 — 1 GB memory behaviour

On a 1 GB board specifically:

- [ ] `free -h` shows ~975 MB total
- [ ] zram0 is ~244 MB
- [ ] The swapfile is 1.0 GiB
- [ ] Home Assistant Core starts without the system running out of memory
- [ ] `MemAvailable` stays above ~150 MB at idle
- [ ] The dashboard loads in a reasonable time
- [ ] An automation that triggers a light runs promptly

See [low-memory.md](low-memory.md) for tuning.

---

## Regression checklist

Run this whenever the board configuration changes:

```bash
./scripts/verify-image.sh --config-only
./scripts/sync-upstream.sh --ref dev --dest /tmp/regression
cd /tmp/regression/buildroot && git apply --check ../../../board/taishan/patches/linux/*.patch
./scripts/build.sh
./scripts/verify-image.sh upstream/output/images/haos_taishan-*.img
```

On hardware: Levels 5, 6 and 8 are the minimum.
