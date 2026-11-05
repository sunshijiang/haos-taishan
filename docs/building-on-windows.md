# Building on Windows with WSL2

Docker is not needed. The Home Assistant OS build is a Buildroot cross
compilation, and Buildroot builds its own toolchain, so a plain Linux
userland is enough. WSL2 gives you that without a virtual machine.

## Why the build runs inside WSL2 and not on the Windows drive

Two reasons, both of them practical:

* **Speed.** The Windows filesystem is reached through a translation layer
  that is several times slower than ext4. A Buildroot build does a huge
  number of small file operations, and the difference is hours.
* **Two file names.** The upstream tree contains two files with a literal
  `\x2d` in their name, for example
  `buildroot-external/rootfs-overlay/usr/lib/systemd/system/etc-NetworkManager-system\x2dconnections.mount`.
  NTFS cannot represent that, so a checkout on the Windows drive leaves
  them out. On ext4 they are there.

So the tree is cloned into the WSL2 filesystem, built there, and only the
finished image is copied back to the Windows drive.

## What you need

* WSL2 with a Debian or Ubuntu distribution
* About 40 GB of free space inside the WSL2 filesystem
* About 8 GB of RAM, 4 cores are enough

## The three steps

### 1. Open WSL2

From PowerShell:

```powershell
wsl
```

If you have no distribution yet, install one:

```powershell
wsl --install -d Ubuntu
```

### 2. Install the build dependencies

Inside WSL2, from the repository:

```bash
cd /mnt/e/sun/TSP/haos-taishan
bash scripts/wsl-setup.sh
```

The package list is the one from the upstream builder image, so the result
is the same image. The script needs `sudo`, which is set up by default in
the Ubuntu distribution.

### 3. Build

```bash
cd /mnt/e/sun/TSP/haos-taishan
bash scripts/wsl-build.sh
```

The first run clones the upstream tree into `~/haos-taishan-build` and
compiles everything from scratch. That takes a few hours.

Watch the progress with a second terminal:

```bash
tail -f ~/haos-taishan-build/build.log
```

When it finishes, the image is in `output/images/` on the Windows drive:

```
output/images/haos_taishan-*.img.xz
output/images/haos_taishan-*.raucb
```

## Options

```bash
bash scripts/wsl-build.sh --jobs 4         # four packages in parallel
bash scripts/wsl-build.sh --ref dev        # build against the current upstream dev
bash scripts/wsl-build.sh --keep-going     # do not stop at the first broken package
```

`--jobs` sets `BR2_JLEVEL`, which is the number of packages compiled at the
same time. The default of `0` means one per core, which is what you want
unless the machine is busy.

## Writing the image to a TF card

The image is on the Windows drive, the card reader is on the Windows side.
Either use a tool such as balenaEtcher or Raspberry Pi Imager, or do it
from WSL2 with a USB pass-through.

The simplest route from WSL2 is to write it from Windows:

```powershell
# Find the drive letter of the card reader, then
wsl -d Ubuntu -- xz -dc /mnt/e/sun/TSP/haos-taishan/output/images/haos_taishan-*.img.xz | dd of=/dev/sdX bs=4M conv=fsync status=progress
```

The `/dev/sdX` path inside WSL2 is the disk that is attached to the
Windows machine, so the card shows up there as well.

## Cleaning up

The build tree is the big one:

```bash
rm -rf ~/haos-taishan-build
```

Keep `~/haos-taishan-build/build.log` if you want to look at the output
again, it is copied to `output/build.log` on the Windows drive anyway.

## If the build fails

The full log is at `~/haos-taishan-build/build.log`, and the last lines are
printed to the console. Search it for the first error:

```bash
grep -nE "Error [0-9]+|error:" ~/haos-taishan-build/build.log | head -20
```

A failing package is usually a network problem while downloading a source
archive. Re-running the script reuses everything that was already built,
so a retry is much faster than the first run.

## What is different from the Docker build

Nothing about the result. The same upstream builder image and the same
Buildroot configuration produce the same output. The differences are only
in how the tools are installed and where the tree lives.

The one thing to keep in mind is that the Docker build runs as the calling
user, so the files in the image belong to that user. The WSL2 build runs
as the WSL2 user, which is also fine.
