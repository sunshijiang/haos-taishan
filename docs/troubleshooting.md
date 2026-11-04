# Troubleshooting

Symptoms, causes and fixes. Ordered roughly by how often they occur.

---

## Workflow problems

### The workflow does not run at all, and the API shows the file path as its name

**Symptom:** a workflow that should trigger does not. In the REST API the
workflow entry keeps the file path as its name:

```
$ curl -s -H "Authorization: Bearer $TOKEN" \
    https://api.github.com/repos/sunshijiang/haos-taishan/actions/workflows
  {"id": 403627579, "name": ".github/workflows/build.yml", ...}
```

A workflow that GitHub parsed correctly shows its `name:` value instead
(`"Build"`). A run created for a workflow that failed to parse has **zero
jobs** and concludes as `failure` immediately.

**Cause:** GitHub's workflow parser rejects the file. In this repository the
cause was an **em dash** (`-`, U+2014) inside a `github-script` block:

```yaml
        with:
          script: |
            const body = `## HAOS Taishan build failed
            ...
               * The upstream tree changed ... - refresh them with ...
            `;
```

Replacing the em dash with a plain hyphen made the file parse again, with
nothing else changed.

**Fix:** keep the workflow files ASCII only. The repository enforces this
with `scripts/check-workflow-chars.py`, which runs as the first step of the
Build workflow:

```bash
$ python3 scripts/check-workflow-chars.py
All workflow files are ASCII only.
```

Common substitutions:

| Character | Code | Replace with |
|:-|:-|:-|
| em dash | U+2014 | `-` |
| en dash | U+2013 | `-` |
| curly quotes | U+2018 / U+2019 | `'` |
| curly double quotes | U+201C / U+201D | `"` |
| ellipsis | U+2026 | `...` |
| non-breaking space | U+00A0 | a space |

**How to diagnose it yourself** when a workflow stops working:

```bash
TOKEN=$(printf "protocol=https\nhost=github.com\n" | git credential fill | grep password= | cut -d= -f2)

# 1. Check whether GitHub parsed it: the name must not be the file path
curl -s -H "Authorization: Bearer $TOKEN" \
  https://api.github.com/repos/sunshijiang/haos-taishan/actions/workflows \
  | python -c "import json,sys;[print(w['name'],w['path']) for w in json.load(sys.stdin)['workflows']]"

# 2. Confirm it parses, by asking GitHub to run it on demand
#    HTTP 204 means the workflow_dispatch trigger was found
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/sunshijiang/haos-taishan/actions/workflows/<id>/dispatches \
  -d '{"ref":"main"}'
```

`scripts/bisect-workflow.py` automates step 2: it commits a candidate file
through the API and reports whether GitHub could parse it.

---

## Build problems

### `git apply` fails for the kernel patch

```
error: patch failed: arch/arm64/boot/dts/rockchip/rk3566-lckfb-tspi.dts:571
```

**Cause:** upstream moved the `&sdhci` node in the device tree, so the line
numbers in the patch are stale.

**Fix:**

```bash
./scripts/sync-upstream.sh --ref dev --dest /tmp/up
cd /tmp/up
grep -n -A8 "^&sdhci" arch/arm64/boot/dts/rockchip/rk3566-lckfb-tspi.dts
```

Update the `@@` line number in the patch to match, then verify:

```bash
cd /tmp/up/buildroot
git apply --check \
    ~/haos-taishan/board/taishan/patches/linux/0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch
```

If upstream already enabled HS200 themselves, delete the patch instead.

### `git apply` fails for the U-Boot patch

Same cause, different file. The `configs/lckfb-tspi-rk3566_defconfig` file
changes when upstream U-Boot is updated.

**Fix:** regenerate the patch against the new file:

```bash
cd /tmp/uboot-ref
git checkout v2026.04
# apply the same edits
git diff > ~/haos-taishan/board/taishan/patches/uboot/0001-configs-lckfb-tspi-rk3566-enable-HAOS-required-options.patch
```

### The build cannot find a kernel config directory

```
ERROR: Could not find .../buildroot-external/kernel/v6.18.y/haos.config
```

**Cause:** upstream renamed the kernel config directory, typically when the
kernel series changes.

**Fix:** update the paths in `configs/taishan_defconfig`:

```
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(BR2_EXTERNAL_HAOS_PATH)/kernel/v6.19.y/kernel-arm64-rockchip.config"
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="$(BR2_EXTERNAL_HAOS_PATH)/kernel/v6.19.y/haos.config ..."
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.19.x"
```

### `linux-check-dotconfig` fails

```
ERROR: kernel config mismatch
```

**Cause:** a kernel config fragment conflicts with what the kernel actually
gained or lost between versions.

**Fix:** the error names the option. Either drop the now-obsolete option from
`board/taishan/kernel.config`, or move it to the correct place. Options that
upstream renamed generally need updating rather than removing.

### The container image fetch fails with 404

```
Error: reading image ... ghcr.io/home-assistant/taishan-homeassistant:...
```

**Cause:** `BR2_PACKAGE_HASSIO_MACHINE` is set to a machine that does not
exist on GHCR.

**Fix:** use `green`. The upstream Core build matrix has no `taishan`
entry; `green` is the RK3566 one.

### The build runs out of disk space

**Fix:** the CI workflow already removes the Android NDK and CodeQL
toolchains. Locally, clear the caches:

```bash
rm -rf .cache/dl .cache/cc .output
```

### On Windows: `error: invalid path '...system\x2dconnections.mount'`

**Cause:** two upstream files contain a literal `\x2d` in their name, which
Windows cannot represent.

**Fix:** use WSL2 rather than Git Bash. `scripts/sync-upstream.sh` already
disables Git's NTFS path protection, but the container build is far more
reliable under WSL2.

---

## Boot problems

### Nothing on the serial console

The Taishan Pi's debug UART is `ttyS2` at 1500000 baud:

```
console=ttyS2,1500000n8 console=tty0
```

Connect with 8N1 at 1500000. Silence usually means the board never reached
U-Boot — suspect the DDR blob.

**Fix:** try a lower-frequency DDR blob, see
[parameters.md](parameters.md#ddr-training-failures).

### The board boots U-Boot but not Linux

Watch the U-Boot output. The usual causes:

| Message | Meaning | Fix |
|:-|:-|:-|
| `Failed to load kernel from any slot` | The kernel partition was not found or is empty | The image was written incorrectly; rewrite it |
| `Error applying DT overlays, restoring original DT` | A DT overlay failed | Usually harmless; the base DTB is restored |
| `Unknown/Expected 'bal' partition` | The partition table does not match | The image is from a different layout; reflash |

### `Failed to mount root filesystem`

```
VFS: Unable to mount root fs
```

**Cause:** the rootfs PARTUUID in the boot script does not match the image.
The boot script hard-codes:

```
bootargs_a: root=PARTUUID=8d3d53e3-6d49-4c38-8349-aff6859e82fd
bootargs_b: root=PARTUUID=a3ec664e-32ce-4665-95ea-7ae90ce9aa20
```

These come from upstream `partitions-os-gpt.cfg`. Verify against your image:

```bash
sfdisk --dump haos_taishan-*.img | grep -i partuuid
```

`scripts/verify-image.sh` checks exactly this.

### The board boots the TF card instead of the eMMC

**Cause:** U-Boot's `spl-boot-order` probes `&sdmmc0` (TF) before `&sdhci`
(eMMC).

**Fix:** remove the TF card, or reflash the eMMC with the card removed.

### The system boots but Home Assistant never comes up

Check the Supervisor and the containers:

```bash
ha supervisor info
ha core info
docker ps -a
journalctl -u docker --no-pager | tail -50
```

Common causes on a 1 GB board: the system ran out of memory during the first
start, when Home Assistant Core indexes its configuration.

### The eMMC seems to corrupt data

**Cause:** the eMMC is running in DDR52 mode instead of HS200. This is a known
RK356x defect.

**Check:** on the device, confirm the link mode:

```bash
cat /sys/kernel/debug/mmc0/ios 2>/dev/null || dmesg | grep -i mmc
```

The output should show HS200, not DDR52.

**Fix:** the kernel patch
`0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch` must be
present. Verify it was applied:

```bash
cd upstream/buildroot
git apply --check ../board/taishan/patches/linux/*.patch
```

---

## Runtime problems

### The device wipe does not trigger

The wipe is triggered by holding the **power button** for about two seconds.
The probe reads the RK809 over I²C0 at address 0x20.

If it does not work:

1. Confirm you are holding the power button, not the Recovery button. The
   Recovery button is an ADC key and is not readable from U-Boot.
2. Check the serial console for `Reset button pressed for 0 seconds`. If the
   message never appears, the I²C read is failing — the probe depends on
   `CONFIG_CMD_I2C` and `CONFIG_SYS_I2C_ROCKCHIP`, both present in the
   mainline board defconfig.
3. The status LED turns on during the countdown (`led user on`). If it does
   not, `CONFIG_CMD_LED` may be missing.

### The WiFi adapter is not detected

The Taishan Pi uses an AP6212 module on SDIO. The kernel must have SDMA
support:

```bash
dmesg | grep -i brcm
ls /sys/bus/platform/drivers/brcmfmac/
```

If the driver does not bind, confirm `CONFIG_MMC_SDHCI_SDMA=y` is in the
kernel config.

### The board is slow or unresponsive

Almost always memory pressure on a 1 GB board. See
[low-memory.md](low-memory.md).

```bash
free -h
cat /proc/pressure/memory
```

### The eMMC has filled up

```bash
df -h
du -sh /mnt/data/*
```

Common culprits: the swapfile (1 GiB minimum), Docker logs, and the
Supervisor's `home-assistant_v2.db`.

---

## Getting help

When reporting a problem, include:

```bash
ha os info            # OS version and hardware
ha core info
ha supervisor info
uname -a
cat /etc/os-release
dmesg | tail -50
```

plus the serial console log from power-on, and the exact upstream commit
from `upstream.pin`.
