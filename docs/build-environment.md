# Build environment

## What the build needs

The HAOS build is a Buildroot cross-compilation. It runs inside the upstream
builder container (`buildroot-external/Dockerfile` in the upstream tree), so
the host only needs Docker and a checkout.

| Requirement | Minimum | Recommended |
|:-|:-|:-|
| Docker | 20.10 | 24+ |
| RAM | 8 GB | 16 GB+ |
| Disk (free) | 40 GB | 60 GB+ |
| CPU | 2 cores | 4+ cores |
| Time | ~2 h | ~40–90 min |

The build compiles the Linux kernel, U-Boot, and a full root filesystem with
Docker, AppArmor and systemd, then assembles the disk image. It is CPU and
disk bound, not RAM bound, but the kernel and the LTO-enabled toolchain are
memory hungry enough that 8 GB gets tight.

## Host packages

Only needed outside the container, for the helper scripts:

```bash
# Debian / Ubuntu
sudo apt install git bash python3 xz-utils docker.io

# Fedora
sudo dnf install git bash python3 xz docker

# macOS (Homebrew)
brew install git bash python3 xz docker
```

`python3` is used by `scripts/sync-upstream.sh` to register the board in
`.github/workflows/matrix.json`.

## Using GitHub Actions (recommended)

The repository builds on every push to `main` that touches the board
configuration, on a schedule, and on demand:

```bash
# Trigger a build manually
gh workflow run build.yml

# Or open the Actions tab and use "Run workflow"
```

Artifacts (`haos_taishan.img.xz` and `haos_taishan.raucb`) are attached to
the run. Use *workflow_dispatch → publish* to also create a GitHub release.

The CI runner is `ubuntu-22.04`. The workflow frees disk space before the
build because the default runner image ships tooling that is not needed
here:

```bash
sudo rm -rf /usr/local/lib/android/sdk/ndk
sudo rm -rf /opt/hostedtoolcache/CodeQL
```

## Local builds

### With the helper script

```bash
./scripts/build.sh
```

This performs the whole flow: sync upstream, build the builder image, run
`make taishan_defconfig`, `make`, and the kernel config check. Caches are
kept in `.cache/` (downloaded sources and ccache) and the output lands in
`.output/`.

```bash
./scripts/build.sh --ref dev        # build against the current upstream dev tip
./scripts/build.sh --ref <sha>      # build against a specific commit
```

### Manually

```bash
# 1. Prepare the upstream tree with the overlay applied
./scripts/sync-upstream.sh --ref $(grep -oE '^[0-9a-f]{40}' upstream.pin | head -1) \
    --dest ./upstream

# 2. Build the builder image
docker build -t haos-builder:local ./upstream

# 3. Configure
docker run --rm --privileged \
    -e BUILDER_UID="$(id -u)" -e BUILDER_GID="$(id -g)" \
    -v "$PWD/upstream:/build" \
    -v "$PWD/.cache:/cache" -v "$PWD/.output:/build/output" \
    haos-builder:local make taishan_defconfig

# 4. Build
docker run --rm --privileged \
    -e BUILDER_UID="$(id -u)" -e BUILDER_GID="$(id -g)" \
    -v "$PWD/upstream:/build" \
    -v "$PWD/.cache:/cache" -v "$PWD/.output:/build/output" \
    haos-builder:local make
```

The `--privileged` flag is required because the build creates loop-mounted
filesystems when it assembles the `data.ext4` partition.

### On Windows with WSL2

Use WSL2 rather than Git Bash or native PowerShell. Two upstream files have a
literal `\x2d` in their name (for example
`buildroot-external/rootfs-overlay/usr/lib/systemd/system/etc-NetworkManager-system\x2dconnections.mount`),
which Windows cannot represent. `scripts/sync-upstream.sh` disables Git's
NTFS path protection to work around it, but the Linux container build itself
is much better behaved inside WSL2.

```bash
# In WSL2
sudo apt install docker.io
sudo service docker start
./scripts/build.sh
```

## Build caching

| Path | Contents | Safe to delete? |
|:-|:-|:-|
| `.cache/dl` | Downloaded source tarballs | Yes, but the next build re-downloads |
| `.cache/cc` | ccache objects | Yes, but the next build is much slower |
| `.output` | Build output and final images | Yes |
| `upstream/` | The upstream checkout with the overlay applied | Yes, it is recreated on every sync |

CI uses the same idea with `/mnt/cache` (persistent between runs) and
`/mnt/output`.

## Verifying a build

```bash
# Configuration-only checks (fast, no image needed)
./scripts/verify-image.sh --config-only

# Full checks on a produced image
./scripts/verify-image.sh upstream/output/images/haos_taishan-*.img
```

The image check verifies that every partition is present and that the two
rootfs PARTUUIDs hard-coded in the boot script are actually in the image. A
mismatch there means the board will boot but find no root filesystem.
