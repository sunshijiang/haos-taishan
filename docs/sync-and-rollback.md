# Upstream sync and rollback

This repository does not vendor the upstream Home Assistant OS tree. It keeps
only the Taishan Pi customisation and pulls upstream at build time. That
choice is what makes an upstream sync cheap and a rollback trivial.

---

## Why not a fork

| Approach | Upstream sync cost | Conflict risk |
|:-|:-|:-|
| Full fork | Merge ~500 changed files, resolve conflicts in Buildroot config by hand | High — upstream reworks `buildroot-external/` regularly |
| Subtree / vendored copy | Same as a fork, plus the history diverges | High |
| **Overlay (this repository)** | `git fetch` + `git checkout` + re-apply two small patches | **Low — the patches are the only thing that can conflict** |

Upstream lands a new kernel roughly every two weeks and reworks the
Buildroot external tree in between. With the overlay approach, a sync that
needs no code change is a one-line pin bump.

---

## The pin

`upstream.pin` records the exact upstream commit the build uses:

```
7093f8afc25d5d110729c8e297c357087c063fb3 2026-10-30 upstream-dev
```

Format: `<40-character sha> <ISO date> <label>`

Pin it rather than tracking a branch because a branch tip moves under you.
The pin makes a build reproducible: the same pin always produces the same
image.

---

## The daily sync

`.github/workflows/sync-upstream.yml` runs at 04:23 UTC every day.

```
      ┌──────────────────┐
      │  upstream dev    │
      └────────┬─────────┘
               │ fetch
               ▼
      ┌──────────────────┐      no change
      │  compare to pin  ├──────────────────────►  job ends quietly
      └────────┬─────────┘
               │ changed
               ▼
      ┌──────────────────┐
      │ apply overlay    │  ◄── fails here?  ──►  failure alert + issue
      │ + check patches  │
      └────────┬─────────┘
               │ OK
               ▼
      ┌──────────────────┐
      │ open / update PR │  "Update upstream to <sha>"
      └────────┬─────────┘
               │ merge
               ▼
      ┌──────────────────┐
      │  Build workflow  │  ──►  new .img.xz + .raucb
      └──────────────────┘
```

### What the sync job actually verifies

Before opening the pull request, the workflow:

1. Clones upstream at the new commit.
2. Applies the Taishan Pi overlay.
3. Runs `git apply --check` on the kernel patch against the new kernel tree.

If the kernel patch no longer applies — for example because upstream moved
the `&sdhci` node in the device tree — the job fails instead of opening a
broken pull request. That is the main thing this repository has to get
right, because a silently mis-patched device tree produces an image that
boots but cannot mount the root filesystem.

### The pull request

The PR body records the old and new SHAs and states that the patches were
verified. Merging it:

* updates `upstream.pin`,
* triggers the **Build** workflow (the workflow watches `upstream.pin`),
* produces a fresh image.

Review the build result before deploying to a device.

---

## Alerting

Failures are never silent.

### On a failed sync

The `notify` job runs and:

1. **Fails the workflow** — the repository status turns red and the failure
   is visible in the Actions tab.
2. **Opens or updates a GitHub issue** labelled `sync-failure`, containing
   the pinned SHA, the new upstream SHA, a link to the run, the name of the
   failing job, and recovery instructions.
3. **Sends an out-of-band notification** if configured:

   | Secret | Destination |
   |-|-|
   | `NTFY_TOPIC` | `https://ntfy.sh/<topic>` |
   | `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` | A Telegram chat |

   Both are optional; without them the issue is still created.

The notification steps read the secrets from the job environment rather than
directly from the `secrets` context, because a secret cannot be used in an
`if` condition:

```yaml
    env:
      NTFY_TOPIC: ${{ secrets.NTFY_TOPIC }}
      TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
      TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}

    steps:
      - name: Send an out-of-band notification
        if: env.NTFY_TOPIC != ''
        run: |
          curl -fsS ... "https://ntfy.sh/$NTFY_TOPIC"
```

### On a failed build

`.github/workflows/alert-build-failure.yml` reacts to a completed `Build`
workflow with a `failure` conclusion and does the same thing, using the
`build-failure` label.

### Configuring notifications

*Settings → Secrets and variables → Actions → New repository secret*:

| Name | Example | Required |
|:-|:-|:-|
| `NTFY_TOPIC` | `haos-taishan-alerts` | Optional |
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | Optional |
| `TELEGRAM_CHAT_ID` | `-1001234567890` | Optional |

To create a Telegram bot, talk to [@BotFather](https://t.me/BotFather); the
chat ID is visible in the bot's `getUpdates` response or in
`https://api.telegram.org/bot<token>/getUpdates`.

---

## Recovering from a failed sync

### The patch no longer applies

This is the expected failure mode after a significant upstream kernel
change.

```bash
# 1. Get the new upstream tree
git clone --depth 1 https://github.com/home-assistant/operating-system.git /tmp/up
cd /tmp/up
git checkout <new-sha>

# 2. See what the patch was trying to change
cd arch/arm64/boot/dts/rockchip
git log --oneline -5 -- rk3566-lckfb-tspi.dts

# 3. Re-apply it by hand, then regenerate the patch
cd /tmp/up
git apply --3way \
    ~/haos-taishan/board/taishan/patches/linux/0001-arm64-dts-rockchip-rk3566-lckfb-tspi-enable-eMMC-HS200.patch
```

If the change is no longer needed — for example if upstream enabled HS200 in
the device tree themselves — drop the patch and delete it from
`board/taishan/patches/linux/`.

Then rebuild and verify:

```bash
./scripts/build.sh
./scripts/verify-image.sh upstream/output/images/haos_taishan-*.img
```

### The board defconfig broke

Upstream sometimes renames a kernel config directory, for example
`kernel/v6.18.y/` to `kernel/v6.19.y/`. Update the three paths in
`configs/taishan_defconfig`:

```
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=…/kernel/v6.19.y/kernel-arm64-rockchip.config
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES=…/kernel/v6.19.y/haos.config …
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.19.x"
```

### The overlay failed to apply

`scripts/sync-upstream.sh` copies `board/taishan/` wholesale and overwrites
`configs/taishan_defconfig`. If upstream renamed one of those paths, the
copy fails loudly. Update the paths in the script.

---

## Rollback

### Rolling back the upstream pin

```bash
# 1. Find the last good commit
git log --oneline -- upstream.pin

# 2. Restore it
git checkout <commit> -- upstream.pin
git commit -m "Rollback upstream pin"
git push
```

The **Build** workflow re-runs and produces an image from the older upstream
tree.

### Rolling back on the device

**Automatic (A/B).** Each slot has three boot attempts. If the new system
fails to boot three times, U-Boot falls back to the other slot. The boot
script resets the counters when no slot has tries left, and RAUC rewrites
`BOOT_ORDER` to drop slots it marked as bad.

**Manual, with an older bundle:**

```bash
# On the device
rauc install /mnt/data/haos_taishan-<older-version>.raucb

# Or via the Supervisor
ha os update --version <older-version>
```

**Manual, with a full image:** write the older `.img.xz` to the TF card and
boot from it. Because the TF card is probed before the eMMC, this works
without touching the eMMC installation.

### Rolling back a bad board change

Every change to `board/taishan/` is a normal git commit, so:

```bash
git log --oneline -- board/taishan/
git revert <commit>
git push
```

The **Build** workflow produces the previous configuration again.

---

## Checking the sync state manually

```bash
# Is upstream ahead of the pin?
./scripts/check-upstream.sh

# Output:
#   UPSTREAM_PINNED_SHA=7093f8afc25d5d110729c8e297c357087c063fb3
#   UPSTREAM_LATEST_SHA=7093f8afc25d5d110729c8e297c357087c063fb3
#   UPSTREAM_UPDATE_AVAILABLE=false
```

Force the sync workflow to run:

```bash
gh workflow run sync-upstream.yml -f force=true
```

---

## Merge cadence

There is no need to sync aggressively. A sensible rhythm:

| When | Action |
|:-|:-|
| Daily | The workflow checks and opens a PR automatically. |
| On the PR | Review the diff, merge if the build passes. |
| Monthly | Merge outstanding PRs, even if nothing changed upstream, to keep the pin current. |
| After a failure | Fix the patches, verify locally, then re-run the workflow. |

Merging a pin bump is safe: the PR is only opened when the patches were
verified to apply, and the build runs before you deploy the image.
